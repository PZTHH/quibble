"""Apply/revert a reproducible BENCHMARK-ONLY patch; not a shipping dependency.
The pristine source and exact patch are retained beside this script.
"""
import pathlib, subprocess, sys, difflib
root = pathlib.Path(__file__).resolve().parents[3]
here = pathlib.Path(__file__).resolve().parent
paths = [root/'Inference/.build/checkouts/mlx-audio-swift/Sources/MLXAudioSTT/Models/Parakeet/ParakeetModel.swift', root/'Inference/Sources/QuibbleInference/LocalInference.swift']
if sys.argv[1:] == ['--restore']:
    for path in paths:
        original = (here/(path.name+'.original')).read_text()
        modified = (here/(path.name+'.modified')).read_text()
        assert path.read_text() == modified, f'Refusing to overwrite unexpected changes: {path}'
        mode = path.stat().st_mode
        path.chmod(mode | 0o200)
        try: path.write_text(original)
        finally: path.chmod(mode)
    print('Restored both source files exactly'); sys.exit()
assert subprocess.check_output(['git','rev-parse','HEAD'], cwd=root/'Inference/.build/checkouts/mlx-audio-swift', text=True).strip() == 'bf14ae0c26e4e85553dd989571cae29d70fa6735'
texts = [p.read_text() for p in paths]
def replace(text, before, after, count=1):
    assert text.count(before) == count, before
    return text.replace(before, after)
s = texts[0]
s = replace(s, '    public var computeDType: DType = .bfloat16', '''    // BENCHMARK ONLY: nil starts a fresh utterance; nonblank tokens advance the tree.
    public var probeVocabularyBias: ((Int?) -> MLXArray)?
    private lazy var compiledBiasedTDTStep = makeCompiledTDTStep(
        decoder: self.decoder, joint: self.joint, blankTokenId: self.blankTokenId, withBias: true)
    public var computeDType: DType = .bfloat16''')
s = replace(s, 'switch tdtDecoderImplementation ?? .serial {', 'switch probeVocabularyBias == nil ? (tdtDecoderImplementation ?? .serial) : .serial {')
s = replace(s, '''            while t < maxLength {
                let frame = featureSeq[0..., t..<(t + 1), 0...]

                let stepOutputs = compiledTDTStep([
                    frame,
                    currentToken,
                    state.hidden!,
                    state.cell!
                ])''', '''            var probeBias = probeVocabularyBias?(nil)
            while t < maxLength {
                let frame = featureSeq[0..., t..<(t + 1), 0...]
                let inputs = [frame, currentToken, state.hidden!, state.cell!]
                let stepOutputs: [MLXArray]
                if let probeBias {
                    stepOutputs = compiledBiasedTDTStep(inputs + [probeBias])
                } else {
                    stepOutputs = compiledTDTStep(inputs)
                }''')
s = replace(s, '''                if token != blankToken {
                    lastToken = token
                    state = (hidden: hidden, cell: cell)''', '''                if token != blankToken {
                    probeBias = probeVocabularyBias?(token)
                    lastToken = token
                    state = (hidden: hidden, cell: cell)''')
s = replace(s, '''    blankTokenId: Int
) -> @Sendable''', '''    blankTokenId: Int,
    withBias: Bool = false
) -> @Sendable''')
s = replace(s, '''        let predToken = tokenLogits.argMax(axis: -1).asType(.int32)
        let decision =''', '''        let unbiasedToken = tokenLogits.argMax(axis: -1).asType(.int32)
        let predToken: MLXArray
        if withBias {
            let biased = (tokenLogits[..<blankTokenId].asType(.float32) + arrays[4]).argMax(axis: -1).asType(.int32)
            // NeMo TDT fusion preserves the acoustic blank/nonblank decision.
            predToken = MLX.where(unbiasedToken .== Int32(blankTokenId), unbiasedToken, biased)
        } else {
            predToken = unbiasedToken
        }
        let decision =''')
i = texts[1]
i = replace(i, 'if engine == .parakeet && parakeet == nil { cohere = nil; parakeet = try ParakeetModel.fromDirectory(speechDirectory) }', '''if engine == .parakeet && parakeet == nil {
            cohere = nil; parakeet = try ParakeetModel.fromDirectory(speechDirectory)
            if CommandLine.arguments.contains("--benchmark"),
               let path = ProcessInfo.processInfo.environment["QUIBBLE_PARAKEET_BIAS_GRAPH"] {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let config = try JSONDecoder().decode(ParakeetProbeGraph.self, from: data)
                let alpha = Float(ProcessInfo.processInfo.environment["QUIBBLE_PARAKEET_BIAS_ALPHA"] ?? "1") ?? 1
                let rows = config.rows.map { MLXArray($0) * alpha }
                for row in rows { MLX.eval(row) }
                var state = 0
                parakeet!.probeVocabularyBias = { token in
                    if let token { state = config.transitions[state][token] } else { state = 0 }
                    return rows[state]
                }
            }
        }''')
i += '''\n// Benchmark-only dense export of the pinned NVIDIA phrase tree.\nprivate struct ParakeetProbeGraph: Decodable {\n    let rows: [[Float]]\n    let transitions: [[Int]]\n}\n'''
for path, old, new in zip(paths, texts, [s,i]):
    backup = here/(path.name+'.original')
    assert not backup.exists() or backup.read_text() == old, 'Existing probe backup does not match'
    backup.write_text(old)
    (here/(path.name+'.modified')).write_text(new)
    (here/(path.name+'.patch')).write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile=str(path.relative_to(root)),tofile=str(path.relative_to(root)))))
    mode = path.stat().st_mode
    path.chmod(mode | 0o200)
    try: path.write_text(new)
    finally: path.chmod(mode)
print('Applied benchmark-only decoder hook to the pinned dependency and inference loader')
