import Foundation
import Observation

struct ContextSnapshot: Codable, Identifiable, Equatable {
    var id = UUID()
    var timestamp = Date()
    var bundleID: String
    var applicationName: String
    var windowTitle: String?
    var text: String
    var status: String
    var source: String? = nil
    var lastSeenAt: Date? = nil
    var sampleCount: Int? = nil
}

@MainActor @Observable
final class ContextStore {
    private(set) var snapshots: [ContextSnapshot] = []
    private(set) var warning: String?
    private let url: URL
    @ObservationIgnored var onWrite: ((Int) -> Void)?
    private var writable = true
    private var lastSavedAt = Date.distantPast
    private(set) var consolidatedSamples = 0
    init(url: URL = URL.applicationSupportDirectory.appending(path: "Conre/context.json")) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { snapshots = try JSONDecoder().decode([ContextSnapshot].self, from: Data(contentsOf: url)).suffix(300).map { $0 } }
        catch { writable = false; warning = "Context history unreadable. Original file preserved; new captures stay in memory." }
    }
    /// Returns true only for a distinct new context; repeats update the last-seen span.
    @discardableResult
    func append(_ snapshot: ContextSnapshot) -> Bool {
        var bounded = snapshot
        bounded.text = String((snapshot.source == "windowOCR" ? ContextReduction.clean(snapshot.text) : snapshot.text).prefix(6000))
        if let index = snapshots.lastIndex(where: {
            $0.bundleID == bounded.bundleID && $0.windowTitle == bounded.windowTitle && $0.source == bounded.source
                && bounded.timestamp.timeIntervalSince($0.lastSeenAt ?? $0.timestamp) < 600
        }) {
            let previous = snapshots[index]
            let normalizeWhitespace = bounded.source == "windowOCR" && !ContextReduction.looksLikeCode(previous.text) && !ContextReduction.looksLikeCode(bounded.text)
            let exact = normalizeWhitespace ? ContextReduction.normalized(previous.text) == ContextReduction.normalized(bounded.text) : previous.text == bounded.text
            let fuzzy = bounded.source == "windowOCR" && bounded.timestamp.timeIntervalSince(previous.timestamp) < 120
                && ContextReduction.similarOCR(previous.text, bounded.text)
            if exact || fuzzy {
                snapshots[index].lastSeenAt = bounded.timestamp
                snapshots[index].sampleCount = (previous.sampleCount ?? 1) + 1
                // Keep the newest OCR wording, without adding another almost-identical record.
                if fuzzy { snapshots[index].text = bounded.text }
                snapshots[index].status = bounded.status
                consolidatedSamples += 1
                if Date().timeIntervalSince(lastSavedAt) >= 60 { persist() }
                return false
            }
        }
        bounded.sampleCount = 1
        snapshots.append(bounded)
        while snapshots.count > 300 || (snapshots.count > 1 && snapshots.reduce(0, { $0 + $1.text.count }) > 500_000) {
            snapshots.removeFirst()
        }
        persist()
        return true
    }
    func flush() { persist() }
    func clear() { snapshots.removeAll(); consolidatedSamples = 0; persist() }
    private func persist() {
        guard writable else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshots)
            try data.write(to: url, options: .atomic)
            onWrite?(data.count)
            lastSavedAt = Date()
            warning = nil
        } catch { warning = "Could not save context: \(error.localizedDescription)" }
    }
}
