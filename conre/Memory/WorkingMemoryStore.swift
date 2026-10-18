import Foundation
import Observation

@MainActor @Observable
final class WorkingMemoryStore {
    private var snapshot = MemorySnapshot()
    @ObservationIgnored private let persistence: any MemoryPersistence
    // A failed read never silently overwrites the original file.
    @ObservationIgnored private var canPersist = true
    private(set) var persistenceMessage: String?

    init(persistence: (any MemoryPersistence)? = nil, seedMockData: Bool = true) {
        let persistence = persistence ?? JSONMemoryPersistence.applicationSupport
        self.persistence = persistence
        do { snapshot = try persistence.load() ?? MemorySnapshot() }
        catch {
            canPersist = false
            persistenceMessage = "Saved memory could not be read. The original file is preserved; changes this session will not be saved."
        }
        if seedMockData { seedMockDataIfNeeded() }
    }

    var threads: [WorkThread] { snapshot.threads.sorted { $0.createdAt < $1.createdAt } }
    var activeThread: WorkThread? { thread(id: snapshot.activeThreadID) }

    func thread(id: UUID?) -> WorkThread? { snapshot.threads.first { $0.id == id } }

    func chronologicalEvents(threadID: UUID? = nil) -> [ActivityEvent] {
        snapshot.events.filter { threadID == nil || $0.threadID == threadID }
            .sorted { $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp }
    }

    func recentEvents(limit: Int = 20) -> [ActivityEvent] {
        Array(chronologicalEvents().suffix(max(0, limit)))
    }

    @discardableResult
    func createThread(title: String, parentThreadID: UUID? = nil, at date: Date = Date()) -> WorkThread {
        precondition(parentThreadID == nil || thread(id: parentThreadID) != nil)
        let thread = WorkThread(title: title, parentThreadID: parentThreadID, createdAt: date, updatedAt: date)
        snapshot.threads.append(thread)
        persist()
        return thread
    }

    @discardableResult
    func setActiveThread(_ id: UUID?) -> Bool {
        guard id == nil || thread(id: id) != nil else { return false }
        for index in snapshot.threads.indices {
            if snapshot.threads[index].id == id {
                snapshot.threads[index].status = .active
                snapshot.threads[index].updatedAt = Date()
            } else if snapshot.threads[index].id == snapshot.activeThreadID {
                snapshot.threads[index].status = .paused
                snapshot.threads[index].updatedAt = Date()
            }
        }
        snapshot.activeThreadID = id
        persist()
        return true
    }

    @discardableResult
    func addEvent(_ event: ActivityEvent) -> Bool {
        guard !snapshot.events.contains(where: { $0.id == event.id }),
              event.threadID == nil || thread(id: event.threadID) != nil,
              event.confidence.isFinite, (0...1).contains(event.confidence) else { return false }
        snapshot.events.append(event)
        touchThread(event.threadID, at: event.timestamp)
        persist()
        return true
    }

    @discardableResult
    func associateEvent(_ eventID: UUID, with threadID: UUID?) -> Bool {
        guard threadID == nil || thread(id: threadID) != nil,
              let index = snapshot.events.firstIndex(where: { $0.id == eventID }) else { return false }
        snapshot.events[index].threadID = threadID
        touchThread(threadID, at: snapshot.events[index].timestamp)
        persist()
        return true
    }

    private func touchThread(_ id: UUID?, at date: Date) {
        if let index = snapshot.threads.firstIndex(where: { $0.id == id }) {
            snapshot.threads[index].updatedAt = max(snapshot.threads[index].updatedAt, date)
        }
    }

    func seedMockDataIfNeeded(now: Date = Date()) {
        guard !snapshot.didSeedMockData, snapshot.events.isEmpty, snapshot.threads.isEmpty else { return }
        let start = now.addingTimeInterval(-29 * 60)
        let thread = WorkThread(title: "Fix student/teacher permissions", createdAt: start, updatedAt: now)
        let examples: [(Int, String, String)] = [
            (0, "Syndeo", "Found a bug involving student and teacher access."),
            (4, "Appwrite", "Opened Appwrite to inspect permissions."),
            (8, "ChatGPT", "Asked ChatGPT about role-based access."),
            (11, "ChatGPT", "Investigated document-level permissions."),
            (16, "Appwrite", "Returned to Appwrite to review read/delete settings."),
            (23, "ChatGPT", "Shared a permissions screenshot with ChatGPT."),
            (29, "Codex", "Submitted implementation instructions to Codex.")
        ]
        snapshot.threads = [thread]
        snapshot.activeThreadID = thread.id
        snapshot.events = examples.map { minute, app, description in
            ActivityEvent(timestamp: start.addingTimeInterval(Double(minute * 60)), applicationName: app,
                          description: description, threadID: thread.id, source: .mock, metadata: ["project": "Syndeo"])
        }
        snapshot.didSeedMockData = true
        persist()
    }

    private func persist() {
        guard canPersist else { return }
        do { try persistence.save(snapshot); persistenceMessage = nil }
        catch { persistenceMessage = "Memory could not be saved. Changes are available this session only. " + error.localizedDescription }
    }
}
