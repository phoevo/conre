import Foundation

struct MemorySnapshot: Codable {
    var version = 1
    var events: [ActivityEvent] = []
    var threads: [WorkThread] = []
    var activeThreadID: UUID? = nil
    var didSeedMockData = false
}

@MainActor
protocol MemoryPersistence {
    func load() throws -> MemorySnapshot?
    func save(_ snapshot: MemorySnapshot) throws
}

/// The store depends on this boundary, rather than on JSON or a particular path.
struct JSONMemoryPersistence: MemoryPersistence {
    let fileURL: URL

    static var applicationSupport: JSONMemoryPersistence {
        let directory = URL.applicationSupportDirectory.appending(path: "Conre", directoryHint: .isDirectory)
        return Self(fileURL: directory.appending(path: "working-memory.json"))
    }

    func load() throws -> MemorySnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let snapshot = try JSONDecoder().decode(MemorySnapshot.self, from: Data(contentsOf: fileURL))
        guard snapshot.version == 1 else { throw CocoaError(.fileReadUnknown) }
        return snapshot
    }

    func save(_ snapshot: MemorySnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
