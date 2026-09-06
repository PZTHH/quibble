import Foundation
import Combine
import Security

/// Owns only Quibble's OpenAI transcription credential. The secret is never published,
/// persisted in preferences, or read while determining setup status.
@MainActor
final class CloudSpeechConnection: ObservableObject {
    @Published private(set) var hasKey = false
    @Published var error: String?

    private static let service = "com.pezhvak.quibble.openai"
    private static let account = "transcription"

    init() { refreshKeyState() }

    private var itemQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: Self.account,
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: false]
    }

    /// Checks metadata only. Never request kSecReturnData here or prefill the setup field.
    func refreshKeyState() {
        var query = itemQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            hasKey = true
            error = nil
        } else if status == errSecItemNotFound {
            hasKey = false
            error = nil
        } else {
            hasKey = false
            error = Self.storageError
        }
    }

    @discardableResult
    func saveKey(_ key: String) -> Bool {
        guard Self.isValidKey(key), let data = key.data(using: .ascii) else {
            error = "Enter an API key without spaces or line breaks, up to 2,048 ASCII characters."
            return false
        }
        // This unsandboxed Mac app deliberately uses the file-based Keychain. Its
        // app ACL works with the existing signing identity; it does not claim the
        // Data Protection Keychain's WhenUnlockedThisDeviceOnly semantics.
        var trustedApplication: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &trustedApplication) == errSecSuccess,
              let trustedApplication else { error = Self.storageError; return false }
        var access: SecAccess?
        guard SecAccessCreate("Quibble OpenAI transcription" as CFString,
                              [trustedApplication] as CFArray, &access) == errSecSuccess,
              let access else { error = Self.storageError; return false }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccess as String: access,
            kSecAttrLabel as String: "Quibble OpenAI transcription"
        ]
        var query = itemQuery
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = itemQuery
            for (key, value) in attributes { item[key] = value }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            error = Self.storageError
            return false
        }
        hasKey = true
        error = nil
        return true
    }

    @discardableResult
    func removeKey() -> Bool {
        var query = itemQuery
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            error = Self.storageError
            return false
        }
        hasKey = false
        error = nil
        return true
    }

    /// Call only for an explicitly requested cloud transcription, immediately before its request.
    /// The caller must not retain the returned value in history, diagnostics, or configuration.
    func apiKey() throws -> String {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            hasKey = false
            throw CredentialError.missing
        }
        guard status == errSecSuccess else { throw CredentialError.unavailable }
        guard let data = result as? Data, let key = String(data: data, encoding: .ascii), Self.isValidKey(key) else {
            throw CredentialError.invalid
        }
        return key
    }

    private static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= 2_048 && key.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
    }

    private static let storageError = "Quibble could not access this Mac’s Keychain. Unlock the login keychain and try again."

    enum CredentialError: LocalizedError {
        case missing, unavailable, invalid
        var errorDescription: String? {
            switch self {
            case .missing: "Add an OpenAI API key in Models, or choose a local speech model."
            case .unavailable: "The OpenAI API key is unavailable. Unlock your Mac and check Keychain access."
            case .invalid: "The stored OpenAI API key cannot be used. Replace it in Models."
            }
        }
    }
}
