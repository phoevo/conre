import Foundation
import Testing
@testable import conre

@MainActor
struct AutomaticSummaryTests {
    let now = Date(timeIntervalSince1970: 10000)
    func snapshot(_ words: Int = 120, offset: Double = 0) -> ContextSnapshot {
        ContextSnapshot(timestamp: now.addingTimeInterval(offset), bundleID: "test.editor", applicationName: "Editor", windowTitle: "theme.swift", text: (0..<words).map { "word\($0)" }.joined(separator: " "), status: "Captured")
    }
    @Test func batchesMeaningfulChangesAndDebounces() {
        var policy = AutomaticSummaryPolicy()
        policy.observe([snapshot()], now: now)
        #expect(!policy.shouldRequest(now: now.addingTimeInterval(24)))
        #expect(policy.shouldRequest(now: now.addingTimeInterval(25)))
        policy.started(at: now.addingTimeInterval(25))
        #expect(!policy.shouldRequest(now: now.addingTimeInterval(100)))
        policy.succeeded(through: now)
        #expect(policy.pending.isEmpty)
    }
    @Test func repeatsAndSmallNoiseDoNotTriggerRequests() {
        var policy = AutomaticSummaryPolicy()
        var value = snapshot()
        policy.observe([value], now: now)
        policy.succeeded(through: now)
        value.lastSeenAt = now.addingTimeInterval(30)
        policy.observe([value], now: now.addingTimeInterval(30))
        value.text += " typo"
        policy.observe([value], now: now.addingTimeInterval(40))
        #expect(policy.pending.isEmpty)
    }
    @Test func capsAndBacksOffAcrossRestoredState() {
        var policy = AutomaticSummaryPolicy()
        policy.observe([snapshot()], now: now)
        policy.requestDates = Array(repeating: now.addingTimeInterval(-200), count: 12)
        #expect(!policy.shouldRequest(now: now.addingTimeInterval(30)))
        policy.requestDates = []
        policy.failed(at: now)
        #expect(!policy.shouldRequest(now: now.addingTimeInterval(599)))
        #expect(policy.shouldRequest(now: now.addingTimeInterval(600)))
    }
    @Test func preservesChangesArrivingDuringRequest() {
        var policy = AutomaticSummaryPolicy()
        let first = snapshot()
        policy.observe([first], now: now)
        var second = snapshot(180, offset: 40)
        second.windowTitle = "other.swift"
        policy.observe([first, second], now: now.addingTimeInterval(40))
        policy.succeeded(through: now)
        #expect(policy.pending.count == 1)
    }
    @Test func oldHistoryDoesNotTriggerAndIdleFlushesSmallUsefulBatch() {
        var policy = AutomaticSummaryPolicy()
        policy.observe([snapshot(offset: -2000)], now: now)
        #expect(policy.pending.isEmpty)
        var fresh = snapshot(24)
        fresh.windowTitle = "new.swift"
        policy.observe([fresh], now: now)
        #expect(!policy.shouldRequest(now: now.addingTimeInterval(30)))
        #expect(policy.shouldRequest(now: now.addingTimeInterval(30), flush: true))
    }
    @Test func removingEligibleHistoryDropsPendingWork() {
        var policy = AutomaticSummaryPolicy()
        policy.observe([snapshot()], now: now)
        policy.observe([], now: now.addingTimeInterval(30))
        #expect(policy.pending.isEmpty)
        #expect(!policy.shouldRequest(now: now.addingTimeInterval(200)))
    }
    @Test func coordinatorGeneratesWithoutAnOpenWindowAndReusesRecap() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "ConreAutoTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["test.editor"], forKey: "approvedApplicationIDs")
        defaults.set(["test.editor"], forKey: "detailedContextIDs")
        let context = ContextStore(url: directory.appending(path: "context.json"))
        let date = Date()
        var observation = snapshot()
        observation.timestamp = date
        context.append(observation)
        let observer = ActivityObserver(defaults: defaults, log: RawObservationLog(url: directory.appending(path: "raw.json")), context: context)
        let summary = SummaryController(url: directory.appending(path: "summary.json"))
        let assistant = WorkAssistant(observer: observer, summary: summary, defaults: defaults,
            readKey: { "synthetic-test-key" }, serviceForKey: { _ in AutoFakeSummarizer() })
        assistant.tick(now: date, idleSeconds: 0)
        #expect(!summary.isGenerating)
        assistant.tick(now: date.addingTimeInterval(26), idleSeconds: 0)
        while assistant.preparing || summary.isGenerating { await Task.yield() }
        #expect(summary.result?.sentence == "You reviewed editor context.")
        #expect((defaults.array(forKey: "automaticSummaryRequests") as? [Date])?.count == 1)
        assistant.tick(now: date.addingTimeInterval(300), idleSeconds: 200)
        assistant.tick(now: date.addingTimeInterval(310), idleSeconds: 0)
        #expect(assistant.recap?.text == summary.result?.sentence)
        assistant.dismissRecap()
        assistant.sessionDidSuspend(now: date.addingTimeInterval(400))
        assistant.sessionDidResume(now: date.addingTimeInterval(4000))
        #expect(assistant.recap != nil)
        assistant.dismissRecap()
        assistant.sessionDidResume(now: date.addingTimeInterval(43200))
        #expect(assistant.recap?.isAI == true)
        assistant.stop()
        summary.clear()
        let late = WorkAssistant(observer: observer, summary: summary, defaults: defaults,
            readKey: { try await Task.sleep(for: .milliseconds(20)); return "synthetic-test-key" }, serviceForKey: { _ in AutoFakeSummarizer() })
        late.tick(now: date.addingTimeInterval(400), idleSeconds: 0)
        late.tick(now: date.addingTimeInterval(426), idleSeconds: 0)
        observer.approve("test.editor", enabled: false)
        while late.preparing || summary.isGenerating { await Task.yield() }
        #expect(summary.result == nil)
        late.stop()
    }
    @Test func disabledCoordinatorDoesNotReadKey() {
        let suite = "ConreAutoDisabled-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "automaticSummariesEnabled")
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let observer = ActivityObserver(defaults: defaults, log: RawObservationLog(url: directory.appending(path: "raw.json")), context: ContextStore(url: directory.appending(path: "context.json")))
        let assistant = WorkAssistant(observer: observer, summary: SummaryController(url: directory.appending(path: "summary.json")), defaults: defaults,
            readKey: { Issue.record("Disabled automation must not read Keychain"); return nil })
        assistant.tick(now: now, idleSeconds: 0)
        #expect(!assistant.preparing)
        #expect(assistant.automaticStatus == "Automatic summaries off")
    }
    @Test func explicitWakeDoesNotWaitForIdleCounterToReset() {
        var policy = ReturnFromIdlePolicy()
        policy.suspended(now: now)
        let resumed = policy.resumed(now: now.addingTimeInterval(3600))
        #expect(resumed)
        #expect(policy.lastWorkAt == now)
        let staleCounter = policy.update(now: now.addingTimeInterval(3601), idleSeconds: 3601, sessionActive: true)
        #expect(!staleCounter)
        #expect(!policy.away)
        let duplicate = policy.resumed(now: now.addingTimeInterval(3602))
        #expect(!duplicate)
        let freshInput = policy.update(now: now.addingTimeInterval(3603), idleSeconds: 0, sessionActive: true)
        #expect(!freshInput)
    }
    @Test func wakeCanRecoverWithoutSleepNotification() {
        var policy = ReturnFromIdlePolicy()
        let resumed = policy.resumed(now: now)
        #expect(resumed)
        #expect(policy.lastWorkAt == now)
    }
    @Test func returnRecapOccursOnceAfterIdleAndAfterSleep() {
        var policy = ReturnFromIdlePolicy()
        let returned1 = policy.update(now: now, idleSeconds: 0, sessionActive: true)
        #expect(!returned1)
        let returned2 = policy.update(now: now.addingTimeInterval(200), idleSeconds: 200, sessionActive: true)
        #expect(!returned2)
        let returned3 = policy.update(now: now.addingTimeInterval(210), idleSeconds: 0, sessionActive: true)
        #expect(returned3)
        let returned4 = policy.update(now: now.addingTimeInterval(215), idleSeconds: 0, sessionActive: true)
        #expect(!returned4)
        let returned5 = policy.update(now: now.addingTimeInterval(220), idleSeconds: 0, sessionActive: false)
        #expect(!returned5)
        let returned6 = policy.update(now: now.addingTimeInterval(230), idleSeconds: 0, sessionActive: true)
        #expect(returned6)
    }
}

private struct AutoFakeSummarizer: ActivitySummarizing {
    func summarize(_ input: SummaryInput) async throws -> SummaryDraft {
        SummaryDraft(summary: "You reviewed editor context.", nodes: [.init(id: "work", parentID: nil, title: "Reviewed editor context", evidenceIDs: [input.evidence[0].id])])
    }
}
