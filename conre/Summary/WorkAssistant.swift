import AppKit
import CoreGraphics
import Observation

struct WorkRecap: Equatable {
    let text: String
    let through: Date
    let isAI: Bool
}

@MainActor @Observable
final class WorkAssistant {
    let summary: SummaryController
    var automaticEnabled: Bool {
        didSet {
            defaults.set(automaticEnabled, forKey: "automaticSummariesEnabled")
            if !automaticEnabled { cancelAutomatic() }
            else { policy.retryAfter = .distantPast; automaticError = nil }
        }
    }
    private(set) var recap: WorkRecap?
    private(set) var automaticStatus = "Waiting for new context"
    private(set) var automaticError: String?
    private(set) var preparing = false
    @ObservationIgnored var onRecapChange: (() -> Void)?
    private let observer: ActivityObserver
    private let defaults: UserDefaults
    @ObservationIgnored private let readKey: () async throws -> String?
    @ObservationIgnored private let serviceForKey: (String) -> any ActivitySummarizing
    private var policy = AutomaticSummaryPolicy()
    private var idle = ReturnFromIdlePolicy()
    private var timer: Timer?
    private var sessionActive = true
    private var tokens: [NSObjectProtocol] = []
    private var lastResultID: UUID?
    private var requestToken = UUID()
    private var automaticRequest = false
    private var credentialTask: Task<Void, Never>?
    private var recapTask: Task<Void, Never>?
    private var recapWaitingForInput = false
    private var recapWakeAt: Date?
    init(observer: ActivityObserver, summary: SummaryController, defaults: UserDefaults = .standard,
         readKey: @escaping () async throws -> String? = { try await SummaryKeychainAccess.shared.read(interactive: false) },
         serviceForKey: @escaping (String) -> any ActivitySummarizing = { OpenAIActivitySummarizer(key: $0) }) {
        self.observer = observer; self.summary = summary; self.defaults = defaults
        self.readKey = readKey; self.serviceForKey = serviceForKey
        automaticEnabled = defaults.object(forKey: "automaticSummariesEnabled") as? Bool ?? true
        policy.requestDates = (defaults.array(forKey: "automaticSummaryRequests") as? [Date]) ?? []
        policy.lastRequestAt = policy.requestDates.max() ?? .distantPast
        policy.retryAfter = defaults.object(forKey: "automaticSummaryRetryAfter") as? Date ?? .distantPast
        lastResultID = summary.result?.id
    }
    func start() {
        guard timer == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sessionDidSuspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sessionDidResume() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.tick() } }
        watchControls(); tick()
    }
    private func watchControls() {
        withObservationTracking { _ = observer.isPaused; _ = automaticEnabled; _ = observer.approvedIDs; _ = observer.detailedIDs } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.timer != nil else { return }
                self.cancelAutomatic(); self.tick(); self.watchControls()
            }
        }
    }
    func sessionDidSuspend(now: Date = Date()) {
        sessionActive = false; idle.suspended(now: now); dismissRecap(); tick(now: now)
    }
    func sessionDidResume(now: Date = Date()) {
        sessionActive = true
        if idle.resumed(now: now), !observer.isPaused {
            recapWakeAt = now
            presentRecap(through: idle.lastWorkAt ?? now, waitForInput: true)
        }
        tick(now: now)
    }
    func stop() {
        timer?.invalidate(); timer = nil
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; tokens.removeAll()
        cancelAutomatic(); dismissRecap()
    }
    func dismissRecap() { recapTask?.cancel(); recapTask = nil; recapWaitingForInput = false; recapWakeAt = nil; recap = nil; onRecapChange?() }
    private func cancelAutomatic() {
        requestToken = UUID(); credentialTask?.cancel(); credentialTask = nil; preparing = false
        if automaticRequest { summary.cancel(); automaticRequest = false }
    }
    func tick(now: Date = Date(), idleSeconds: TimeInterval? = nil) {
        let seconds = idleSeconds ?? CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        if recapWaitingForInput, sessionActive, seconds < 10,
           now.addingTimeInterval(-max(0, seconds)) > (recapWakeAt ?? now).addingTimeInterval(1) {
            recapWaitingForInput = false; recapWakeAt = nil; scheduleRecapDismissal()
        }
        let returned = idle.update(now: now, idleSeconds: seconds, sessionActive: sessionActive)
        if returned, !observer.isPaused { presentRecap(through: idle.lastWorkAt ?? now) }
        if observer.isPaused {
            cancelAutomatic(); automaticStatus = "Paused"; dismissRecap(); return
        }
        if summary.result?.id != lastResultID, let result = summary.result {
            lastResultID = result.id; policy.succeeded(through: result.input.end)
            policy.lastRequestAt = max(policy.lastRequestAt, result.createdAt)
            if recap != nil { presentRecap(through: idle.lastWorkAt ?? now, waitForInput: recapWaitingForInput) }
        }
        guard automaticEnabled else { automaticStatus = "Automatic summaries off"; return }
        guard sessionActive else { cancelAutomatic(); return }
        if observer.context.snapshots.isEmpty { policy.discardPending(); cancelAutomatic(); automaticStatus = "Waiting for context"; return }
        let eligible = observer.context.snapshots.filter { observer.approvedIDs.contains($0.bundleID) && observer.detailedIDs.contains($0.bundleID) }
        policy.observe(eligible, now: now)
        guard !preparing, !summary.isGenerating else { automaticStatus = "Updating your activity tree"; return }
        guard policy.shouldRequest(now: now, flush: idle.away || returned) else {
            automaticStatus = automaticError != nil ? "Update needs attention" : policy.pending.isEmpty ? "Up to date" : "Gathering new context"
            return
        }
        beginAutomatic(at: now)
    }
    private func beginAutomatic(at now: Date) {
        let cutoff = idle.away ? min(now, idle.lastWorkAt ?? now) : now
        let eligible = observer.context.snapshots.filter { observer.approvedIDs.contains($0.bundleID) && observer.detailedIDs.contains($0.bundleID) }
        let input = SummaryInput.build(eligible, since: cutoff.addingTimeInterval(-3600), until: cutoff)
        guard !input.evidence.isEmpty else { return }
        preparing = true
        let token = UUID(); requestToken = token
        credentialTask = Task { [weak self] in
            defer {
                if let self, self.requestToken == token { self.preparing = false; self.credentialTask = nil }
            }
            do {
                guard let key = try await self?.readKey() else {
                    throw SummaryFailure.unavailable("Add your OpenAI key in Advanced to enable automatic summaries.")
                }
                guard let self, self.requestToken == token, self.automaticEnabled, !self.observer.isPaused, self.sessionActive, !self.summary.isGenerating else { return }
                let eligibleIDs = Set(self.observer.context.snapshots.filter {
                    self.observer.approvedIDs.contains($0.bundleID) && self.observer.detailedIDs.contains($0.bundleID)
                }.map { $0.id.uuidString })
                guard input.evidence.allSatisfy({ eligibleIDs.contains($0.id) }) else { self.policy.discardPending(); return }
                self.preparing = false; self.automaticRequest = true; self.automaticError = nil
                self.policy.started(at: Date())
                self.defaults.set(self.policy.requestDates, forKey: "automaticSummaryRequests")
                self.summary.generate(input, using: self.serviceForKey(key)) { [weak self] success in
                    guard let self, self.requestToken == token else { return }
                    self.automaticRequest = false
                    if success { self.policy.succeeded(through: now); self.automaticError = nil }
                    else { self.fail(at: Date(), message: self.summary.error ?? "Automatic update could not finish.") }
                }
            } catch {
                guard let self, self.requestToken == token else { return }
                self.preparing = false; self.fail(at: Date(), message: error.localizedDescription)
            }
        }
    }
    private func fail(at now: Date, message: String) {
        policy.failed(at: now); defaults.set(policy.retryAfter, forKey: "automaticSummaryRetryAfter")
        automaticError = message; automaticStatus = "Update needs attention"
    }
    private func presentRecap(through date: Date, waitForInput: Bool = false) {
        let text: String
        let through: Date
        let ai: Bool
        if let result = summary.result, date.timeIntervalSince(result.input.end) >= -180 {
            text = result.sentence; through = result.input.end; ai = true
        } else if let last = observer.context.snapshots.filter({ $0.timestamp <= date && !$0.text.isEmpty }).max(by: { $0.timestamp < $1.timestamp }) {
            // A factual fallback while the AI catches up; never imply inferred intent.
            let title = (last.windowTitle ?? "").replacingOccurrences(of: "\n", with: " ")
            text = "You were using \(last.applicationName)\(title.isEmpty ? "" : " — " + String(title.prefix(140)))."
            through = min(last.latestDate, date); ai = false
        } else { return }
        recap = WorkRecap(text: text, through: through, isAI: ai); onRecapChange?()
        recapTask?.cancel(); recapTask = nil
        recapWaitingForInput = waitForInput
        if !waitForInput { recapWakeAt = nil; scheduleRecapDismissal() }
    }
    private func scheduleRecapDismissal() {
        recapTask?.cancel()
        recapTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(18))
            guard !Task.isCancelled else { return }
            self?.dismissRecap()
        }
    }
}
