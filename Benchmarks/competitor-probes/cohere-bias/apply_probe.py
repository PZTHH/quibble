"""Reversible offline, nonstreaming Cohere decoder experiment. Not shipping code."""
import pathlib,subprocess,sys,difflib
root=pathlib.Path(__file__).resolve().parents[3];here=pathlib.Path(__file__).resolve().parent
paths=[root/'Inference/.build/checkouts/mlx-audio-swift/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribe.swift',root/'Inference/Sources/QuibbleInference/LocalInference.swift']
def write(path,text):
    mode=path.stat().st_mode;path.chmod(mode|0o200)
    try:path.write_text(text)
    finally:path.chmod(mode)
if sys.argv[1:]==['--restore']:
    for path in paths:
        assert path.read_text()==(here/(path.name+'.modified')).read_text(),f'Unexpected changes: {path}'
        write(path,(here/(path.name+'.original')).read_text())
    print('Restored both source files exactly');sys.exit()
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=root/'Inference/.build/checkouts/mlx-audio-swift',text=True).strip()=='bf14ae0c26e4e85553dd989571cae29d70fa6735'
texts=[p.read_text() for p in paths]
def replace(s,a,b):
    assert s.count(a)==1,a
    return s.replace(a,b)
s=replace(texts[0],'    private var tokenizer: CohereTranscribeTokenizer?','''    private var tokenizer: CohereTranscribeTokenizer?
    public var probeVocabularyBias: ((Int?) -> MLXArray)?''')
s=replace(s,'''        for pos in context.promptLength..<(context.promptLength + maxGenerationTokens) {
            let token = sample(logits: context.logits, temperature: generationParameters.temperature)
            generated.append(token)''','''        var probeBias = probeVocabularyBias?(nil)
        for pos in context.promptLength..<(context.promptLength + maxGenerationTokens) {
            let logits = probeBias.map { context.logits.asType(.float32) + $0 } ?? context.logits
            let token = sample(logits: logits, temperature: generationParameters.temperature)
            generated.append(token)
            probeBias = probeVocabularyBias?(token)''')
i=replace(texts[1],'''if (engine == .cohere || engine == .cohere4bit) && cohere == nil { parakeet = nil; cohere = try CohereTranscribeModel.fromDirectory(speechDirectory) }''','''if (engine == .cohere || engine == .cohere4bit) && cohere == nil {
            parakeet = nil; cohere = try CohereTranscribeModel.fromDirectory(speechDirectory)
            if CommandLine.arguments.contains("--benchmark"),
               let path = ProcessInfo.processInfo.environment["QUIBBLE_COHERE_BIAS_GRAPH"] {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let config = try JSONDecoder().decode(CohereProbeGraph.self, from: data)
                let tokenizer = try CohereTranscribeTokenizer(modelDir: speechDirectory, config: cohere!.config)
                guard zip(config.phrases, config.tokens).allSatisfy({ tokenizer.encode(text: $0.0) == $0.1 }) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let alpha = Float(ProcessInfo.processInfo.environment["QUIBBLE_COHERE_BIAS_ALPHA"] ?? "1") ?? 1
                let rows = config.rows.map { MLXArray($0) * alpha }
                for row in rows { MLX.eval(row) }
                var state = 0
                cohere!.probeVocabularyBias = { token in
                    if let token { state = config.transitions[state][token] } else { state = 0 }
                    return rows[state]
                }
            }
        }''')
i+='''\nprivate struct CohereProbeGraph: Decodable {
    let phrases: [String]
    let tokens: [[Int]]
    let rows: [[Float]]
    let transitions: [[Int]]
}\n'''
for path,old,new in zip(paths,texts,[s,i]):
    backup=here/(path.name+'.original');assert not backup.exists() or backup.read_text()==old
    backup.write_text(old);(here/(path.name+'.modified')).write_text(new)
    (here/(path.name+'.patch')).write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile=str(path.relative_to(root)),tofile=str(path.relative_to(root)))))
    write(path,new)
print('Applied benchmark-only Cohere logits hook')
