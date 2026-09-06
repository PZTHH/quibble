"""Reversible benchmark hook for transcript likelihoods using one audio encoder pass."""
import pathlib,sys,difflib,subprocess
root=pathlib.Path(__file__).resolve().parents[3];here=pathlib.Path(__file__).resolve().parent
paths=[root/'Inference/.build/checkouts/mlx-audio-swift/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribe.swift', root/'Inference/Sources/QuibbleInference/LocalInference.swift',root/'App/VocabularyBenchmark.swift',root/'App/QuibbleApp.swift']
def write(p,s):
 mode=p.stat().st_mode;p.chmod(mode|0o200)
 try:p.write_text(s)
 finally:p.chmod(mode)
if sys.argv[1:]==['--restore']:
 for p in paths:
  assert p.read_text()==(here/(p.name+'.modified')).read_text(),str(p)
  write(p,(here/(p.name+'.original')).read_text())
 sys.exit()
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=root/'Inference/.build/checkouts/mlx-audio-swift',text=True).strip()=='bf14ae0c26e4e85553dd989571cae29d70fa6735'
old=[p.read_text() for p in paths];new=list(old)
new[0]+='''
public extension CohereTranscribeModel {
    /// Benchmark only: total log probability of each complete candidate, with shared acoustic prefill.
    func probeTranscriptLikelihoods(audio: MLXArray, transcripts: [String]) -> [[Float]] {
        let initial = encodeAndPrefill(audio: audio, generationParameters: STTGenerateParameters(maxTokens: 512, language: "en"))
        guard let tokenizer else { return [] }
        let eos = tokenizer.encode(text: "<|endoftext|>").first ?? 0
        return transcripts.map { text in
            let ids = tokenizer.encode(text: text) + [eos]
            var cache = initial.cache, logits = initial.logits
            var scores: [Float] = []
            for (index, token) in ids.enumerated() {
                let f = logits.asType(.float32)
                let score = f[token] - logSumExp(f)
                scores.append(score.item(Float.self))
                if index + 1 == ids.count { break }
                let next = decoder(inputIds: MLXArray([Int32(token)]).expandedDimensions(axis: 0),
                    positions: MLXArray([Int32(initial.promptLength + index)]).expandedDimensions(axis: 0),
                    encoderHiddenStates: initial.adapterOut, selfAttentionMask: nil, crossAttentionMask: nil, cache: cache)
                cache = next.1
                logits = lmHead(next.0[0, -1]); eval(logits)
            }
            return scores
        }
    }
}
'''
new[1]+='''
extension LocalInference {
    public func probeAcousticVocabulary(file: URL, root: URL, transcripts: [String]) async throws -> [[Float]] {
        _ = try await load(root: root, withCleanup: false, engine: .cohere4bit)
        let (_, audio) = try loadAudioArray(from: file, sampleRate: 16_000)
        return cohere!.probeTranscriptLikelihoods(audio: audio, transcripts: transcripts)
    }
}
'''
new[2]+='''
extension VocabularyBenchmark {
    private struct AcousticFixture: Decodable {
        let audio: String
        let name: String
        let transcripts: [String]
        let expectedIndex: Int
    }
    @MainActor static func runAcoustic(_ args: [String]) async throws {
        guard args.count == 4 else { throw CocoaError(.fileReadInvalidFileName) }
        let fixtures = try JSONDecoder().decode([AcousticFixture].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let engine = LocalInference()
        var rows: [[String: Any]] = []
        for fixture in fixtures {
            let start = ProcessInfo.processInfo.systemUptime
            let scores = try await engine.probeAcousticVocabulary(file: URL(fileURLWithPath: fixture.audio),
                root: URL(fileURLWithPath: args[1]), transcripts: fixture.transcripts)
            let totals = scores.map { $0.reduce(0, +) }
            rows.append(["name": fixture.name, "transcripts": fixture.transcripts, "expectedIndex": fixture.expectedIndex,
                "scores": scores, "totals": totals, "seconds": ProcessInfo.processInfo.systemUptime - start])
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
            print("\\(fixture.name): \\(totals)")
        }
    }
}
'''
key='        if args.contains("--s1-vocabulary-fixtures") {'
assert new[3].count(key)==1
new[3]=new[3].replace(key,'''        if args.contains("--acoustic-vocabulary-fixtures") {
            do { try await VocabularyBenchmark.runAcoustic(Array(args.dropFirst())) }
            catch { FileHandle.standardError.write(Data("Acoustic benchmark failed: \\(error)\\n".utf8)); exit(1) }
            return
        }
'''+key)
for p,a,b in zip(paths,old,new):
 backup=here/(p.name+'.original');assert not backup.exists() or backup.read_text()==a
 backup.write_text(a);(here/(p.name+'.modified')).write_text(b)
 (here/(p.name+'.patch')).write_text(''.join(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile=str(p.relative_to(root)),tofile=str(p.relative_to(root)))))
 write(p,b)
print('Applied acoustic candidate scoring probe')
