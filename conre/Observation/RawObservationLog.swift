import Foundation
import Observation

struct RawObservation: Codable, Identifiable, Equatable {
    var id = UUID()
    var timestamp = Date()
    var bundleID: String
    var applicationName: String
    var processID: Int32
    var windowTitle: String?
    var windowStatus: String
    var observedUntil: Date? = nil
    var intentNote: String? = nil
}

@MainActor @Observable
final class RawObservationLog {
    private(set) var events: [RawObservation] = []
    private(set) var warning: String?
    private let url: URL
    @ObservationIgnored var onWrite: ((Int) -> Void)?
    private var writable = true
    private var activeID: UUID?
    private var lastSavedAt = Date.distantPast
    init(url: URL = URL.applicationSupportDirectory.appending(path: "Conre/raw-observations.json")) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { events = try JSONDecoder().decode([RawObservation].self, from: Data(contentsOf: url)) }
        catch { writable = false; warning = "Raw log could not be read. Original file preserved; new observations stay in memory." }
    }
    func append(_ event: RawObservation) {
        endSession(at: event.timestamp)
        var event = event
        event.observedUntil = event.timestamp
        events.append(event)
        activeID = event.id
        if events.count > 5000 { events.removeFirst(events.count - 5000) }
        persist()
    }
    func confirmActivity(at date: Date = Date()) {
        guard let activeID, let index = events.lastIndex(where: { $0.id == activeID }) else { return }
        events[index].observedUntil = max(events[index].timestamp, date)
        if Date().timeIntervalSince(lastSavedAt) >= 30 { persist() }
    }
    func endSession(at date: Date = Date()) {
        guard activeID != nil else { return }
        confirmActivity(at: date)
        activeID = nil
        persist()
    }
    func clear() { activeID = nil; events.removeAll(); persist() }
    private func persist() {
        guard writable else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(events)
            try data.write(to: url, options: .atomic)
            onWrite?(data.count)
            lastSavedAt = Date()
            warning = nil
        } catch { warning = "Could not save raw observations: \(error.localizedDescription)" }
    }
}
