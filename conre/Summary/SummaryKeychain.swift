import Foundation
import Security
import LocalAuthentication

struct SummaryKeychain {
    private let service: String
    nonisolated init(service: String = "phoevo.conre.openai") { self.service = service }
    private nonisolated var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
    }
    nonisolated func read(interactive: Bool = true) throws -> String? {
        var request = query
        if !interactive {
            let context = LAContext(); context.interactionNotAllowed = true
            request[kSecUseAuthenticationContext as String] = context
        }
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Self.failure(status, operation: "read") }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw SummaryFailure.unavailable("The saved Keychain entry contains no readable API key. Save your key again to replace this entry.")
        }
        return key
    }
    nonisolated func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), !key.contains(where: \.isWhitespace) else { throw SummaryFailure.unavailable("Enter a valid OpenAI API key.") }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Self.failure(update, operation: "save") }
        var request = query.merging(attributes) { _, new in new }
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess else { throw Self.failure(status, operation: "save") }
    }
    nonisolated func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.failure(status, operation: "remove") }
    }
    nonisolated static func failure(_ status: OSStatus, operation: String) -> SummaryFailure {
        let explanation: String
        switch status {
        case errSecUserCanceled: explanation = "Keychain access was cancelled. Retry and complete the macOS prompt if it appears."
        case errSecAuthFailed: explanation = "Keychain authorization failed. Retry and allow this signed copy of Conre in the macOS prompt."
        case errSecInteractionNotAllowed: explanation = "Keychain needs user interaction. Keep Conre in front, unlock your login keychain if locked, and retry."
        case errSecNotAvailable: explanation = "Keychain is currently unavailable. Retry after unlocking your Mac."
        case errSecMissingEntitlement: explanation = "This build lacks the required Keychain access. Run the signed Conre build from Xcode."
        default: explanation = "Keychain could not \(operation) the saved key. Retry; if it persists, report the code below."
        }
        return .unavailable("\(explanation) (Keychain \(status))")
    }
}

// Security's synchronous calls may wait for a macOS authorization dialog.
// Keep them on a dedicated actor rather than blocking SwiftUI's main actor.
actor SummaryKeychainAccess {
    static let shared = SummaryKeychainAccess()
    private let store = SummaryKeychain()
    func read(interactive: Bool = true) async throws -> String? { try store.read(interactive: interactive) }
    func saveAndVerify(_ value: String) throws -> String {
        try store.save(value)
        guard let verified = try store.read(), verified == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw SummaryFailure.unavailable("The key was written but could not be verified. Retry Keychain access before generating.")
        }
        return verified
    }
    func remove() throws { try store.remove() }
}
