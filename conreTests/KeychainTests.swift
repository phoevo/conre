import Foundation
import Security
import Testing
@testable import conre

@MainActor
struct KeychainTests {
    @Test func failuresDistinguishAuthorizationFromUnavailableStorage() {
        let cancelled = SummaryKeychain.failure(errSecUserCanceled, operation: "read").localizedDescription
        let denied = SummaryKeychain.failure(errSecAuthFailed, operation: "read").localizedDescription
        let interaction = SummaryKeychain.failure(errSecInteractionNotAllowed, operation: "read").localizedDescription
        #expect(cancelled.contains("cancelled"))
        #expect(!cancelled.contains("Unlock"))
        #expect(denied.contains("authorization failed"))
        #expect(interaction.contains("user interaction"))
        #expect(interaction.contains(String(errSecInteractionNotAllowed)))
    }
    @Test func rejectsInvalidKeyBeforeCreatingEntry() throws {
        let store = SummaryKeychain(service: "phoevo.conre.test." + UUID().uuidString)
        #expect(throws: SummaryFailure.self) { try store.save("not-a-key") }
        #expect(try store.read() == nil)
    }
    @Test func signedHostCanRoundTripTemporaryKey() throws {
        let store = SummaryKeychain(service: "phoevo.conre.test." + UUID().uuidString)
        defer { try? store.remove() }
        #expect(try store.read() == nil)
        try store.save("sk-conre-synthetic-test-value")
        #expect(try store.read() == "sk-conre-synthetic-test-value")
        try store.save("sk-conre-synthetic-replacement")
        #expect(try store.read() == "sk-conre-synthetic-replacement")
        try store.remove()
        #expect(try store.read() == nil)
    }
}
