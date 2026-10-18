import Foundation
import Testing
@testable import conre

@MainActor
struct conreTests {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ConreTests-" + UUID().uuidString).appending(path: "memory.json")
    }

    @Test func addingAndChronologicalRetrieval() {
        let store = WorkingMemoryStore(persistence: JSONMemoryPersistence(fileURL: location()), seedMockData: false)
        let later = ActivityEvent(timestamp: Date(timeIntervalSince1970: 200), applicationName: "Codex", description: "Later", source: .observed)
        let earlier = ActivityEvent(timestamp: Date(timeIntervalSince1970: 100), applicationName: "Appwrite", description: "Earlier", source: .mock)
        #expect(store.addEvent(later))
        #expect(store.addEvent(earlier))
        #expect(!store.addEvent(later))
        #expect(store.chronologicalEvents().map(\.id) == [earlier.id, later.id])
        #expect(store.recentEvents(limit: 1) == [later])
        #expect(store.recentEvents(limit: 0).isEmpty)
    }

    @Test func threadAssociationAndActiveThread() {
        let store = WorkingMemoryStore(persistence: JSONMemoryPersistence(fileURL: location()), seedMockData: false)
        let parent = store.createThread(title: "Syndeo")
        let child = store.createThread(title: "Permissions", parentThreadID: parent.id)
        let event = ActivityEvent(applicationName: "Appwrite", description: "Inspected permissions", source: .mock)
        #expect(store.addEvent(event))
        #expect(store.associateEvent(event.id, with: child.id))
        #expect(store.chronologicalEvents(threadID: child.id).first?.threadID == child.id)
        #expect(store.setActiveThread(parent.id))
        #expect(store.setActiveThread(child.id))
        #expect(store.activeThread?.id == child.id)
        #expect(store.thread(id: parent.id)?.status == .paused)
        #expect(!store.associateEvent(event.id, with: UUID()))
        #expect(store.associateEvent(event.id, with: nil))
        #expect(store.chronologicalEvents(threadID: child.id).isEmpty)
    }

    @Test func persistenceAcrossReloads() {
        let persistence = JSONMemoryPersistence(fileURL: location())
        let first = WorkingMemoryStore(persistence: persistence, seedMockData: false)
        let thread = first.createThread(title: "Permissions")
        first.setActiveThread(thread.id)
        let event = ActivityEvent(applicationName: "ChatGPT", description: "Asked about roles", threadID: thread.id, source: .mock)
        first.addEvent(event)
        let second = WorkingMemoryStore(persistence: persistence, seedMockData: false)
        #expect(second.chronologicalEvents() == [event])
        #expect(second.activeThread?.id == thread.id)
        #expect(second.persistenceMessage == nil)
    }

    @Test func mockSeedingOnlyOnce() {
        let persistence = JSONMemoryPersistence(fileURL: location())
        let first = WorkingMemoryStore(persistence: persistence)
        let original = first.chronologicalEvents()
        first.seedMockDataIfNeeded()
        let second = WorkingMemoryStore(persistence: persistence)
        #expect(original.count == 7)
        #expect(second.chronologicalEvents() == original)
        #expect(second.threads.count == 1)
        #expect(original.allSatisfy { $0.source == .mock })
    }

    @Test func corruptPersistenceIsPreserved() throws {
        let url = location()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("broken JSON".utf8)
        try corrupt.write(to: url)
        let store = WorkingMemoryStore(persistence: JSONMemoryPersistence(fileURL: url))
        #expect(store.persistenceMessage != nil)
        #expect(store.chronologicalEvents().count == 7)
        store.addEvent(ActivityEvent(applicationName: "Demo", description: "Session only", source: .mock))
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test func missingFileAndInvalidConfidence() {
        let store = WorkingMemoryStore(persistence: JSONMemoryPersistence(fileURL: location()), seedMockData: false)
        #expect(store.persistenceMessage == nil)
        #expect(store.chronologicalEvents().isEmpty)
        #expect(!store.addEvent(ActivityEvent(applicationName: "Demo", description: "Invalid", confidence: 2, source: .mock)))
    }
}
