"""Reversible native Whisper initial-prompt experiment."""
import pathlib,sys,difflib,subprocess
root=pathlib.Path(__file__).resolve().parents[3];here=pathlib.Path(__file__).resolve().parent
paths=[root/'Inference/.build/checkouts/mlx-audio-swift/Sources/MLXAudioSTT/Models/Whisper/WhisperModel.swift',root/'Inference/Sources/QuibbleInference/LocalInference.swift',root/'App/VocabularyBenchmark.swift',root/'App/QuibbleApp.swift']
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
def replace(s,a,b):
 assert s.count(a)==1,a
 return s.replace(a,b)
new[0]=replace(new[0],'    private var tokenizer: WhisperTokenizer?', '    private var tokenizer: WhisperTokenizer?\n    public var probeInitialPrompt: String = ""')
new[0]=replace(new[0],'''        let promptIds = tokenizer.buildPromptTokens(
            language: generationParameters.language,
            task: "transcribe"
        )''','''        let basePrompt = tokenizer.buildPromptTokens(language: generationParameters.language, task: "transcribe")
        var promptIds = basePrompt
        if !probeInitialPrompt.isEmpty, let previous = tokenizer.prevSotId {
            let hintTokens = tokenizer.inner.encode(text: " " + probeInitialPrompt.trimmingCharacters(in: .whitespacesAndNewlines), addSpecialTokens: false)
            promptIds = [previous] + Array(hintTokens.suffix(config.maxTargetPositions / 2 - 1)) + basePrompt
        }''')
# Language metadata must refer to the actual transcription prefix after previous-text hints.
new[0]=new[0].replace('let langTokenId = promptIds[1]', 'let langTokenId = basePrompt[1]')
new[1]=replace(new[1],'    private var cohere: CohereTranscribeModel?', '    private var cohere: CohereTranscribeModel?\n    private var probeWhisper: WhisperModel?')
new[1]+='''
extension LocalInference {
    public func probeWhisperVocabulary(file: URL, directory: URL, words: [String]) async throws -> String {
        if probeWhisper == nil { probeWhisper = try await WhisperModel.fromDirectory(directory) }
        let (_, audio) = try loadAudioArray(from: file, sampleRate: 16_000)
        probeWhisper!.probeInitialPrompt = words.joined(separator: ", ")
        return probeWhisper!.generate(audio: audio, generationParameters: STTGenerateParameters(maxTokens: 256, language: "en")).text
    }
}
'''
new[2]+='''
extension VocabularyBenchmark {
    private struct WhisperFixture: Decodable {
        let name: String
        let audio: String
        let expected: String
        let baselines: [String: String]
    }
    private struct WhisperFixtures: Decodable { let words: [String]; let cases: [WhisperFixture] }
    @MainActor static func runWhisper(_ args: [String]) async throws {
        guard args.count == 4 else { throw CocoaError(.fileReadInvalidFileName) }
        let fixtures = try JSONDecoder().decode(WhisperFixtures.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let engine = LocalInference()
        let entries = fixtures.words.map { VocabularyEntry(preferred: $0) }
        var rows: [[String: Any]] = []
        for hints in [false, true] {
            for fixture in fixtures.cases {
                for run in 0..<2 {
                    let start = ProcessInfo.processInfo.systemUptime
                    let text = try await engine.probeWhisperVocabulary(file: URL(fileURLWithPath: fixture.audio),
                        directory: URL(fileURLWithPath: args[1]), words: hints ? fixtures.words : [])
                    let elapsed = ProcessInfo.processInfo.systemUptime - start
                    var projected: [String: String] = [:]
                    for (name, raw) in fixture.baselines { projected[name] = VocabularyEdits.project(text, onto: raw, entries: entries).text }
                    rows.append(["case": fixture.name, "hints": hints, "run": run, "response": text,
                        "expected": fixture.expected, "projected": projected, "seconds": elapsed, "memory": await engine.memoryUsage()])
                    try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
                    print("\\(hints) \\(fixture.name): \\(text)")
                }
            }
        }
    }
}
'''
new[3]=replace(new[3],'        if args.contains("--s1-vocabulary-fixtures") {','''        if args.contains("--whisper-vocabulary-fixtures") {
            do { try await VocabularyBenchmark.runWhisper(Array(args.dropFirst())) }
            catch { FileHandle.standardError.write(Data("Whisper benchmark failed: \\(error)\\n".utf8)); exit(1) }
            return
        }
        if args.contains("--s1-vocabulary-fixtures") {''')
for p,a,b in zip(paths,old,new):
 backup=here/(p.name+'.original');assert not backup.exists() or backup.read_text()==a
 backup.write_text(a);(here/(p.name+'.modified')).write_text(b)
 (here/(p.name+'.patch')).write_text(''.join(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile=str(p.relative_to(root)),tofile=str(p.relative_to(root)))))
 write(p,b)
print('Applied Whisper initial-prompt benchmark hook')
