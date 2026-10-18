import Foundation

struct ActivityEvent: Identifiable, Codable, Equatable {
    enum Source: String, Codable { case mock, observed, aiGenerated }

    var id: UUID = UUID()
    var timestamp: Date = Date()
    var applicationName: String
    var applicationBundleIdentifier: String? = nil
    var description: String
    var threadID: UUID? = nil
    var confidence: Double = 1
    var source: Source
    var metadata: [String: String]? = nil
}
