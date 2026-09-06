import Foundation

/// Resolves the model folder a build starts from when the user has not chosen one.
///
/// A development build stamps the checkout's `Models` folder into the bundle. A
/// distribution build clears that setting, so the key is present but empty. An
/// empty or whitespace-only value is not a usable path and must fall back to the
/// per-user location rather than resolving to the bundle's working directory.
public enum ModelRootDefault {
    public static func path(configured: String?, fallback: String) -> String {
        guard let trimmed = configured?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return fallback }
        return trimmed
    }
}
