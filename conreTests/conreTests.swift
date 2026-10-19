import Foundation
import AppKit
import CoreText
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

@MainActor
struct ObservationTests {
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ConreObservationTests-\(UUID().uuidString)/raw.json")
    }
    @Test func approvalAndPausePersist() throws {
        let name = "ConreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let observer = ActivityObserver(defaults: defaults, log: RawObservationLog(url: url()))
        #expect(!observer.mayObserve("com.example.Editor"))
        observer.approve("com.example.Editor", enabled: true)
        #expect(observer.mayObserve("com.example.Editor"))
        observer.togglePause()
        #expect(!observer.mayObserve("com.example.Editor"))
        let reloaded = ActivityObserver(defaults: defaults, log: RawObservationLog(url: url()))
        #expect(reloaded.isPaused)
        #expect(reloaded.approvedIDs.contains("com.example.Editor"))
        reloaded.togglePause()
        reloaded.approve("com.example.Editor", enabled: false)
        #expect(!reloaded.mayObserve("com.example.Editor"))
        #expect(reloaded.log.events.isEmpty)
    }
    @Test func rawLogRoundTripAndClear() {
        let location = url()
        let log = RawObservationLog(url: location)
        let event = RawObservation(bundleID: "com.example.Editor", applicationName: "Editor", processID: 42, windowTitle: nil, windowStatus: "sandboxRestricted")
        log.append(event)
        let reloaded = RawObservationLog(url: location)
        #expect(reloaded.events.first?.id == event.id)
        #expect(reloaded.events.first?.observedUntil == event.timestamp)
        reloaded.clear()
        #expect(RawObservationLog(url: location).events.isEmpty)
    }
    @Test func unreadableLogIsPreserved() throws {
        let location = url()
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("invalid".utf8)
        try original.write(to: location)
        let log = RawObservationLog(url: location)
        log.append(RawObservation(bundleID: "test", applicationName: "Test", processID: 1, windowStatus: "unavailable"))
        #expect(log.warning != nil)
        #expect(try Data(contentsOf: location) == original)
    }
}

@MainActor
struct MigrationTests {
    @Test func copiesHistoryWithoutOverwritingOrRemovingOriginals() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ConreMigration-\(UUID().uuidString)")
        let old = root.appending(path: "old")
        let new = root.appending(path: "new")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let original = Data("original".utf8)
        try original.write(to: old.appending(path: "raw-observations.json"))
        try LegacyStorageMigration.copyMissingFiles(from: old, to: new)
        #expect(try Data(contentsOf: new.appending(path: "raw-observations.json")) == original)
        let current = Data("current".utf8)
        try current.write(to: new.appending(path: "raw-observations.json"))
        try LegacyStorageMigration.copyMissingFiles(from: old, to: new)
        #expect(try Data(contentsOf: new.appending(path: "raw-observations.json")) == current)
        #expect(try Data(contentsOf: old.appending(path: "raw-observations.json")) == original)
    }
}

@MainActor
struct ActivitySessionTests {
    private func event(_ time: Double, end: Double?, title: String, app: String = "browser", note: String? = nil) -> RawObservation {
        RawObservation(timestamp: Date(timeIntervalSince1970: time), bundleID: app, applicationName: app,
                       processID: 42, windowTitle: title, windowStatus: "available",
                       observedUntil: end.map { Date(timeIntervalSince1970: $0) }, intentNote: note)
    }
    @Test func groupsContinuousAppVisitsAndKeepsWindowSequence() {
        let events = [event(0, end: 10, title: "Appwrite"), event(10, end: 25, title: "Permissions")]
        let sessions = ActivitySession.grouped(events)
        #expect(sessions.count == 1)
        #expect(sessions[0].knownDuration == 25)
        #expect(sessions[0].titles == ["Appwrite", "Permissions"])
    }
    @Test func separatesGapsIntentChangesAndReturns() {
        let sessions = ActivitySession.grouped([
            event(0, end: 10, title: "Appwrite"),
            event(20, end: 30, title: "Appwrite"),
            event(30, end: 40, title: "Appwrite", note: "Fix roles"),
            event(40, end: 50, title: "Editor", app: "editor"),
            event(50, end: 60, title: "Appwrite", note: "Fix roles")])
        #expect(sessions.count == 5)
        #expect(sessions[2].intentNote == "Fix roles")
    }
    @Test func legacyRecordsHaveUnknownDuration() throws {
        let old = event(0, end: nil, title: "Old")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "observedUntil"); json.removeValue(forKey: "intentNote")
        let decoded = try JSONDecoder().decode(RawObservation.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(ActivitySession.grouped([decoded])[0].knownDuration == nil)
    }
    @Test func closedSessionsDoNotAccumulatePausedOrRelaunchTime() {
        let url = FileManager.default.temporaryDirectory.appending(path: "ConreSession-\(UUID().uuidString)/raw.json")
        let log = RawObservationLog(url: url)
        log.append(event(0, end: nil, title: "Appwrite"))
        log.confirmActivity(at: Date(timeIntervalSince1970: 10))
        log.endSession(at: Date(timeIntervalSince1970: 12))
        log.confirmActivity(at: Date(timeIntervalSince1970: 50))
        let reloaded = RawObservationLog(url: url)
        reloaded.confirmActivity(at: Date(timeIntervalSince1970: 100))
        #expect(reloaded.events.first?.observedUntil == Date(timeIntervalSince1970: 12))
        log.append(event(60, end: nil, title: "Appwrite"))
        #expect(ActivitySession.grouped(log.events).count == 2)
    }
}

@MainActor
struct IntentTests {
    @Test func noteIsTrimmedBoundedAndPersisted() throws {
        let name = "ConreIntentTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let url = FileManager.default.temporaryDirectory.appending(path: "ConreIntent-\(UUID().uuidString)/raw.json")
        let observer = ActivityObserver(defaults: defaults, log: RawObservationLog(url: url))
        observer.setIntentNote("  Fix student permissions  ")
        #expect(observer.intentNote == "Fix student permissions")
        let restored = ActivityObserver(defaults: defaults, log: RawObservationLog(url: url))
        #expect(restored.intentNote == "Fix student permissions")
        restored.setIntentNote(String(repeating: "x", count: 600))
        #expect(restored.intentNote.count == 500)
        restored.setIntentNote("   ")
        #expect(restored.intentNote.isEmpty)
    }
}

@MainActor
struct ContextTests {
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ConreContext-\(UUID().uuidString)/context.json")
    }
    @Test func boundedDeduplicatedHistoryReloadsAndClears() {
        let location = url()
        let store = ContextStore(url: location)
        let snapshot = ContextSnapshot(bundleID: "editor", applicationName: "Editor", text: "function example()", status: "captured")
        store.append(snapshot); store.append(snapshot)
        #expect(store.snapshots.count == 1)
        store.flush()
        #expect(ContextStore(url: location).snapshots == store.snapshots)
        store.append(ContextSnapshot(bundleID: "editor", applicationName: "Editor", text: String(repeating: "x", count: 7000), status: "partial"))
        #expect(store.snapshots.last?.text.count == 6000)
        store.clear()
        #expect(ContextStore(url: location).snapshots.isEmpty)
    }
    @Test func corruptedContextFileIsNeverOverwritten() throws {
        let location = url()
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("broken".utf8)
        try original.write(to: location)
        let store = ContextStore(url: location)
        store.append(ContextSnapshot(bundleID: "app", applicationName: "App", text: "text", status: "captured"))
        store.clear()
        #expect(store.warning != nil)
        #expect(try Data(contentsOf: location) == original)
    }
    @Test func detailedCaptureRequiresSeparateApprovalAndRespectsPauseAndRevoke() throws {
        let name = "ConreContextTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let observer = ActivityObserver(defaults: defaults, log: RawObservationLog(url: url()), context: ContextStore(url: url()))
        observer.enableDetailedContext("example.editor", enabled: true)
        #expect(!observer.mayCaptureContext("example.editor"))
        observer.approve("example.editor", enabled: true)
        #expect(!observer.mayCaptureContext("example.editor"))
        observer.enableDetailedContext("example.editor", enabled: true)
        #expect(observer.mayCaptureContext("example.editor"))
        observer.togglePause()
        #expect(!observer.mayCaptureContext("example.editor"))
        observer.togglePause()
        observer.approve("example.editor", enabled: false)
        #expect(!observer.mayCaptureContext("example.editor"))
        #expect(!observer.detailedIDs.contains("example.editor"))
        #expect(observer.context.snapshots.isEmpty)
    }
}

struct PageContentSearchTests {
    private struct Tree {
        let roles: [String: String]
        let edges: [String: [String]]
        var hidden: Set<String> = []
        func find(focused: String? = nil, window: String = "window") -> String? {
            PageContentSearch.find(window: window, focused: focused,
                role: { roles[$0] ?? "" },
                parent: { node in edges.first(where: { $0.value.contains(node) })?.key },
                children: { edges[$0] ?? [] }, hidden: { hidden.contains($0) }, equal: { $0 == $1 }, canContinue: { true })
        }
    }
    @Test func ignoresBookmarksAndFindsPageWhenAddressBarIsFocused() {
        let tree = Tree(roles: ["window": "AXWindow", "toolbar": "AXToolbar", "bookmarks": "AXStaticText", "address": "AXTextField", "container": "AXGroup", "page": "AXWebArea"],
                        edges: ["window": ["toolbar", "container"], "toolbar": ["bookmarks", "address"], "container": ["page"]])
        #expect(tree.find(focused: "address") == "page")
    }
    @Test func neverFallsBackToBrowserInterfaceWhenPageIsMissing() {
        let tree = Tree(roles: ["window": "AXWindow", "toolbar": "AXToolbar", "bookmarks": "AXStaticText"],
                        edges: ["window": ["toolbar"], "toolbar": ["bookmarks"]])
        #expect(tree.find() == nil)
    }
    @Test func prefersFocusedPageAndIgnoresHiddenPages() {
        let tree = Tree(roles: ["window": "AXWindow", "old": "AXWebArea", "page": "AXWebArea", "text": "AXStaticText"],
                        edges: ["window": ["old", "page"], "page": ["text"]], hidden: ["old"])
        #expect(tree.find(focused: "text") == "page")
        #expect(tree.find() == "page")
    }
    @Test func doesNotTakeFocusedPageFromAnotherWindow() {
        let tree = Tree(roles: ["window": "AXWindow", "other": "AXWindow", "page": "AXWebArea"], edges: ["other": ["page"]])
        #expect(tree.find(focused: "page") == nil)
    }
}

struct CaptureEvidenceTests {
    @Test func titleAndControlsAreNotReportedAsBodyText() {
        let titleOnly = CaptureEvidence.result(content: ["ChatGPT"], interface: ["ChatGPT", "New chat"], windowTitle: "ChatGPT", bounded: false, browser: false, nodeCount: 8)
        #expect(titleOnly.text.isEmpty)
        #expect(titleOnly.status.contains("No body text captured"))
        let controlsOnly = CaptureEvidence.result(content: [], interface: ["Search", "Copy", "Share"], windowTitle: "ChatGPT", bounded: true, browser: false, nodeCount: 160)
        #expect(controlsOnly.text.isEmpty)
        #expect(controlsOnly.status.contains("Limit reached"))
    }
    @Test func preservesActualTextAndReportsLimitsHonestly() {
        let result = CaptureEvidence.result(content: ["Students cannot read their profiles"], interface: ["Copy"], windowTitle: "ChatGPT", bounded: true, browser: false, nodeCount: 160)
        #expect(result.text.contains("Students cannot read their profiles"))
        #expect(result.status == "Partial body text · Limit reached")
    }
}

struct AppAccessibilitySupportTests {
    @Test func onlyKnownAppsReceiveRendererSupportRequests() {
        #expect(AppAccessibilitySupport.attribute(for: "com.openai.codex") == "AXManualAccessibility")
        #expect(AppAccessibilitySupport.attribute(for: "com.microsoft.VSCode") == "AXManualAccessibility")
        #expect(AppAccessibilitySupport.attribute(for: "com.google.Chrome") == "AXEnhancedUserInterface")
        #expect(AppAccessibilitySupport.attribute(for: "com.apple.systempreferences") == nil)
        #expect(AppAccessibilitySupport.attribute(for: "unknown.app") == nil)
    }
}

struct ConversationRegionTests {
    @Test func prioritizesConversationOverLargeSidebar() {
        let edges = ["page": ["layout"], "layout": ["sidebar", "main"], "sidebar": (0..<100).map { "chat-\($0)" }, "main": ["conversation"], "conversation": ["message"]]
        let selected = PageContentSearch.contentRegion(root: "page", focused: "message",
            role: { $0 == "page" ? "AXWebArea" : "AXGroup" }, label: { $0 == "conversation" ? "Conversation" : "" },
            parent: { node in edges.first(where: { $0.value.contains(node) })?.key }, children: { edges[$0] ?? [] }, equal: { $0 == $1 }, canContinue: { true })
        #expect(selected == "conversation")
    }
    @Test func findsConversationWhenFocusIsOutsideThePage() {
        let edges = ["page": ["layout"], "layout": ["sidebar", "conversation"]]
        let selected = PageContentSearch.contentRegion(root: "page", focused: "address",
            role: { $0 == "page" ? "AXWebArea" : "AXGroup" }, label: { $0 == "conversation" ? "Conversation" : "" },
            parent: { node in edges.first(where: { $0.value.contains(node) })?.key }, children: { edges[$0] ?? [] }, equal: { $0 == $1 }, canContinue: { true })
        #expect(selected == "conversation")
    }
    @Test func neverSelectsConversationFromAnotherPage() {
        let selected = PageContentSearch.contentRegion(root: "page", focused: "other-conversation",
            role: { _ in "AXGroup" }, label: { $0 == "other-conversation" ? "Conversation" : "" },
            parent: { _ in nil }, children: { _ in [] }, equal: { $0 == $1 }, canContinue: { true })
        #expect(selected == "page")
    }
}


@MainActor
struct VisualFallbackTests {
    @Test func requiresSeparateApprovalAndStopsAfterPauseOrRevocation() throws {
        let name = "ConreVisualTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let root = FileManager.default.temporaryDirectory.appending(path: "ConreVisual-\(UUID().uuidString)")
        let observer = ActivityObserver(defaults: defaults, log: RawObservationLog(url: root.appending(path: "raw.json")), context: ContextStore(url: root.appending(path: "context.json")))
        observer.enableVisualFallback("test.editor", enabled: true)
        #expect(!observer.mayCaptureVisual("test.editor"))
        observer.approve("test.editor", enabled: true)
        observer.enableDetailedContext("test.editor", enabled: true)
        #expect(!observer.mayCaptureVisual("test.editor"))
        observer.enableVisualFallback("test.editor", enabled: true)
        #expect(observer.mayCaptureVisual("test.editor"))
        observer.togglePause()
        #expect(!observer.mayCaptureVisual("test.editor"))
        observer.togglePause()
        observer.enableDetailedContext("test.editor", enabled: false)
        #expect(!observer.visualIDs.contains("test.editor"))
        observer.enableDetailedContext("test.editor", enabled: true)
        observer.enableVisualFallback("test.editor", enabled: true)
        observer.approve("test.editor", enabled: false)
        #expect(!observer.mayCaptureVisual("test.editor"))
        #expect(observer.context.snapshots.isEmpty)
    }
    @Test func windowMatchingNeverCrossesAppsOrGuessesByTitleAlone() {
        let frame = CGRect(x: 0, y: 30, width: 800, height: 600)
        let target = VisualWindowTarget(pid: 42, windowID: nil, frame: frame, title: "Conversation")
        #expect(VisualWindowCapture.matches(target, id: 1, pid: 42, frame: frame, title: "Conversation"))
        #expect(!VisualWindowCapture.matches(target, id: 1, pid: 43, frame: frame, title: "Conversation"))
        #expect(!VisualWindowCapture.matches(target, id: 1, pid: 42, frame: frame.offsetBy(dx: 100, dy: 0), title: "Conversation"))
        #expect(!VisualWindowCapture.matches(target, id: 1, pid: 42, frame: frame, title: "Other window"))
        let exact = VisualWindowTarget(pid: 42, windowID: 99, frame: frame, title: "Conversation")
        #expect(!VisualWindowCapture.matches(exact, id: 98, pid: 42, frame: frame, title: "Conversation"))
    }
    @Test func localOCRReadsSyntheticTextWithoutScreenAccess() throws {
        let context = try #require(CGContext(data: nil, width: 1100, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1100, height: 180))
        let text = NSAttributedString(string: "Student profile permission error", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 42, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.black.cgColor])
        context.textPosition = CGPoint(x: 30, y: 80)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        let image = try #require(context.makeImage())
        let result = try VisualWindowCapture.recognizeText(in: image).lowercased()
        #expect(result.contains("student profile permission error"))
    }
    @Test func oldCapturesRemainReadableWithoutSourceField() throws {
        let snapshot = ContextSnapshot(bundleID: "test", applicationName: "Test", text: "Old text", status: "captured")
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ContextSnapshot.self, from: data)
        #expect(decoded.source == nil)
        #expect(decoded.text == "Old text")
    }
}


@MainActor
struct ContextEfficiencyTests {
    @Test func repeatedOCRIsCoalescedWithoutGrowingHistory() {
        let url = FileManager.default.temporaryDirectory.appending(path: "ContextEfficiency-\(UUID().uuidString)/context.json")
        let store = ContextStore(url: url)
        let prose = (0..<80).map { "word\($0)" }.joined(separator: " ")
        let first = ContextSnapshot(timestamp: Date(timeIntervalSince1970: 100), bundleID: "app", applicationName: "App", text: prose, status: "OCR", source: "windowOCR")
        #expect(store.append(first))
        var repeatView = first
        repeatView.id = UUID(); repeatView.timestamp = Date(timeIntervalSince1970: 115)
        repeatView.text = prose + " PM"
        #expect(!store.append(repeatView))
        #expect(store.snapshots.count == 1)
        #expect(store.snapshots[0].text == repeatView.text)
        #expect(store.snapshots[0].timestamp == first.timestamp)
        #expect(store.snapshots[0].lastSeenAt == repeatView.timestamp)
        store.flush()
        #expect(ContextStore(url: url).snapshots[0].sampleCount == 2)
    }
    @Test func smallCodeAndNumberChangesArePreserved() {
        let url = FileManager.default.temporaryDirectory.appending(path: "ContextCode-\(UUID().uuidString)/context.json")
        let store = ContextStore(url: url)
        let original = "func validate() { return role == 1 }"
        let edited = "func validate() { return role != 1 }"
        #expect(store.append(ContextSnapshot(bundleID: "editor", applicationName: "Editor", text: original, status: "captured", source: "accessibility")))
        #expect(store.append(ContextSnapshot(bundleID: "editor", applicationName: "Editor", text: edited, status: "captured", source: "accessibility")))
        #expect(store.snapshots.count == 2)
        let numberContext = String(repeating: "Student profile permission requires a matching role. ", count: 20)
        #expect(!ContextReduction.similarOCR(numberContext + "Role 1", numberContext + "Role 2"))
        #expect(store.append(ContextSnapshot(bundleID: "editor", applicationName: "Editor", text: "def validate():\n    return 1", status: "OCR", source: "windowOCR")))
        #expect(store.append(ContextSnapshot(bundleID: "editor", applicationName: "Editor", text: "def validate():\nreturn 1", status: "OCR", source: "windowOCR")))
        #expect(!ContextReduction.similarOCR(String(repeating: original, count: 20), String(repeating: edited, count: 20)))
        #expect(ContextReduction.clean("Copy\nfunc validate() {\n    return 1\n}").contains("    return 1"))
    }
    @Test func filterIsConservativeAndScheduleBacksOff() {
        #expect(ContextReduction.clean("Copy\nStudents cannot read profiles\nShare") == "Students cannot read profiles")
        #expect(ContextReduction.nextDelay(current: 12, changed: false) == 24)
        #expect(ContextReduction.nextDelay(current: 48, changed: false) == 60)
        #expect(ContextReduction.nextDelay(current: 60, changed: true) == 12)
        #expect(!ContextReduction.similarOCR(String(repeating: "old context ", count: 60), String(repeating: "new unrelated activity ", count: 60)))
    }
    @Test func visualGateIgnoresTinyNoiseButDetectsLargeChanges() {
        let original = [UInt8](repeating: 128, count: 2560)
        var cursor = original; cursor[0] = 255
        var changed = original
        for index in 0..<500 { changed[index] = 255 }
        #expect(VisualWindowCapture.similarImage(original, cursor))
        #expect(!VisualWindowCapture.similarImage(original, changed))
        #expect(!VisualWindowCapture.similarImage([], []))
    }
}

@MainActor
struct PolishTests {
    @Test func changesShowOnlyNewEvidenceAndKeepAppBoundaries() {
        let first = ContextSnapshot(timestamp: Date(timeIntervalSince1970: 1), bundleID: "chat", applicationName: "Chat", windowTitle: "Roles", text: "Student cannot read profiles\nCheck document permissions", status: "captured")
        let next = ContextSnapshot(timestamp: Date(timeIntervalSince1970: 2), bundleID: "chat", applicationName: "Chat", windowTitle: "Roles", text: "Student cannot read profiles\nTry a student session", status: "captured")
        let other = ContextSnapshot(timestamp: Date(timeIntervalSince1970: 3), bundleID: "editor", applicationName: "Editor", windowTitle: "Roles", text: next.text, status: "captured")
        let changes = ContextChange.build([first, next, other])
        #expect(changes.count == 3)
        #expect(changes[1].added == ["Try a student session"])
        #expect(changes[1].removedCount == 1)
        #expect(changes[0].first)
        #expect(ContextChange.build([first, first]).count == 1)
    }
    @Test func partialTextIsNotFailureAndPermissionIsDistinct() {
        #expect(CaptureHealth.classify(text: "Some evidence", status: "Partial body text · Limit reached") == .partial)
        #expect(!CaptureHealth.partial.needsAttention)
        #expect(CaptureHealth.classify(text: "", status: "Enable Screen Recording permission") == .permission)
        #expect(CaptureHealth.classify(text: "", status: "No body text captured · AX requests 50") == .unavailable)
        #expect(CaptureHealth.classify(text: "", status: "Secure field focused · Capture skipped") == .paused)
    }
    @Test func bodyEvidenceDoesNotAppendInterfaceLabels() {
        let result = CaptureEvidence.result(content: ["Permission denied for student"], interface: ["Share", "Copy", "Profile menu"], windowTitle: "Appwrite", bounded: false, browser: true, nodeCount: 20)
        #expect(result.text == "Permission denied for student")
    }
    @Test func OCRSeparatesClearReadingColumnButKeepsAmbiguousLayouts() {
        let body = (0..<4).map { index in OCRTextLine(text: "This is a long meaningful conversation line number \(index) about student permissions.", bounds: CGRect(x: 0.3, y: 0.8 - Double(index) * 0.1, width: 0.6, height: 0.03), confidence: 0.9) }
        let sidebar = OCRTextLine(text: "Old unrelated chat", bounds: CGRect(x: 0.01, y: 0.8, width: 0.15, height: 0.03), confidence: 0.9)
        #expect(OCRContentFilter.select([sidebar] + body).count == 4)
        #expect(OCRContentFilter.select([sidebar, body[0]]).count == 2)
    }
    @Test func editorRootRequiresFocusedEditorToBelongToWindow() {
        let edges = ["window": ["toolbar", "editor"], "other": ["wrong-editor"]]
        let found = PageContentSearch.editorRegion(window: "window", focused: "editor", role: { $0.contains("editor") ? "AXTextArea" : "AXGroup" }, label: { _ in "" }, parent: { node in edges.first(where: { $0.value.contains(node) })?.key }, children: { edges[$0] ?? [] }, equal: { $0 == $1 }, canContinue: { true })
        #expect(found == "editor")
        let wrong = PageContentSearch.editorRegion(window: "window", focused: "wrong-editor", role: { $0.contains("editor") ? "AXTextArea" : "AXGroup" }, label: { _ in "" }, parent: { node in edges.first(where: { $0.value.contains(node) })?.key }, children: { edges[$0] ?? [] }, equal: { $0 == $1 }, canContinue: { true })
        #expect(wrong == "window")
    }
    @Test func modeSelectionPreservesExplicitVisualConsent() throws {
        let suite = "ConrePolish-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        let observer = ActivityObserver(defaults: defaults, log: RawObservationLog(url: root.appending(path: "raw.json")), context: ContextStore(url: root.appending(path: "context.json")))
        observer.setCaptureMode("test.editor", mode: .text)
        #expect(observer.captureMode(for: "test.editor") == .text)
        #expect(!observer.mayCaptureVisual("test.editor"))
        observer.setCaptureMode("test.editor", mode: .visual)
        #expect(observer.mayCaptureVisual("test.editor"))
        observer.setCaptureMode("test.editor", mode: .activity)
        #expect(!observer.detailedIDs.contains("test.editor"))
        #expect(!observer.visualIDs.contains("test.editor"))
        observer.setCaptureMode("test.editor", mode: .off)
        #expect(!observer.mayObserve("test.editor"))
    }
    @Test func metricsCountActualWritesAndCompletedWork() {
        let metrics = CapturePerformance()
        metrics.capture(seconds: 0.2, ocr: true, reused: false)
        metrics.capture(seconds: 0.1, ocr: false, reused: true)
        metrics.write(bytes: 512)
        #expect(metrics.attempts == 2)
        #expect(metrics.ocrRuns == 1)
        #expect(metrics.reusedOCR == 1)
        #expect(metrics.diskWrites == 1)
        #expect(metrics.writtenBytes == 512)
    }
    @Test func benchmarkChangeProjection() throws {
        let snapshots = (0..<200).map { index in ContextSnapshot(timestamp: Date(timeIntervalSince1970: Double(index)), bundleID: "editor", applicationName: "Editor", windowTitle: "permissions.swift", text: (0..<50).map { "Line \($0): student permission context" }.joined(separator: "\n") + "\nRevision \(index)", status: "captured", source: "accessibility") }
        let start = ProcessInfo.processInfo.systemUptime
        var count = 0
        for _ in 0..<10 { count = ContextChange.build(snapshots).count }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 10
        #expect(count == 200)
        let report: [String: Any] = ["records": 200, "linesPerRecord": 51, "iterations": 10, "averageProjectionMilliseconds": milliseconds]
        try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted).write(to: URL(fileURLWithPath: "/private/tmp/conre-polish/benchmark.json"))
    }
}
