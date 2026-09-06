import AppKit
import QuibbleCore

@MainActor
enum VocabularySpelling {
    private static var known: [String: Bool] = [:]
    static func process(_ text: String, with processor: VocabularyProcessor) -> VocabularyResult {
        processor.process(text) { word in
            if let cached = known[word] { return cached }
            // Only plausible candidates reach this lookup. Do not scan every word, request
            // suggestions, modify the system dictionary, or poll while the app is idle.
            let checker = NSSpellChecker.shared
            let language = checker.availableLanguages.first { $0 == "en_US" } ?? checker.availableLanguages.first { $0.hasPrefix("en") }
            let recognized: Bool
            if let language {
                recognized = checker.checkSpelling(of: word, startingAt: 0, language: language,
                    wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
            } else { recognized = true } // Unknown language support: do not guess.
            if known.count >= 512 { known.removeAll(keepingCapacity: true) }
            known[word] = recognized
            return recognized
        }
    }
}
