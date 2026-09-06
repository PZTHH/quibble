import SwiftUI

/// Small, bundled publisher marks shared across the model library and workflows.
/// Identify the original model family, not its community quantization repository.
struct ModelIcon: View {
    let modelID: String
    var size: CGFloat = 42

    private var brand: (asset: String, name: String)? {
        if modelID.hasPrefix("cohere") { return ("cohere", "Cohere Labs") }
        if ["parakeet", "canary", "nemotron"].contains(where: { modelID.hasPrefix($0) }) { return ("nvidia", "NVIDIA") }
        if modelID.hasPrefix("qwen") { return ("qwen", "Qwen") }
        if modelID.hasPrefix("whisper") || modelID.hasPrefix("openai-") { return ("openai", "OpenAI") }
        if modelID.hasPrefix("moonshine") { return ("moonshine", "Moonshine AI") }
        if modelID.hasPrefix("granite") { return ("granite", "IBM Granite") }
        if modelID == "s1-mini" { return ("superwhisper", "Superwhisper") }
        return nil
    }

    var body: some View {
        Group {
            if let brand {
                Image("ModelBrand-" + brand.asset)
                    .resizable().scaledToFit()
                    .background(.white)
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(.primary.opacity(0.06))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(.primary.opacity(0.08)))
        .accessibilityLabel(publisherLabel)
        .help(publisherLabel)
    }
    private var publisherLabel: String {
        if let brand { return "Model publisher: " + brand.name }
        return "Model"
    }
}
