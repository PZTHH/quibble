import Foundation

/// Decides whether a streamed text result may replace its input.
public enum RefinementCompletion {
    public static func text(_ output: String, stoppedNormally: Bool?) -> String? {
        let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stoppedNormally == true, DictationWorkflow.isUsableOutput(clean),
              !clean.contains("<think>"), !clean.contains("<|im_") else { return nil }
        return clean
    }
}
