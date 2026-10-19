import AppKit
import ApplicationServices
import Security
import Observation

enum ObservationStatus: String {
    case choosing, waiting, paused, sleeping, switched, windowChanged, recording, appOnly, titleUnavailable, saveWarning
    var symbol: String {
        switch self {
        case .choosing: "checklist"
        case .waiting: "arrow.trianglehead.2.clockwise.rotate.90"
        case .paused: "pause.fill"
        case .sleeping: "moon.zzz.fill"
        case .switched: "arrow.triangle.branch"
        case .windowChanged: "rectangle.on.rectangle"
        case .recording: "pencil.line"
        case .appOnly: "lock.shield"
        case .titleUnavailable: "rectangle.dashed"
        case .saveWarning: "exclamationmark.triangle"
        }
    }
}

@MainActor @Observable
final class ActivityObserver {
    private(set) var isPaused: Bool
    private(set) var approvedIDs: Set<String>
    private(set) var statusKind: ObservationStatus = .choosing
    private(set) var status = "Choose apps to observe"
    private(set) var windowPermission = "Window metadata unavailable"
    private(set) var isRecording = false
    private(set) var accessibilityGranted = false
    private(set) var intentNote: String
    let context: ContextStore
    var contextSettingsPresented = false
    private(set) var visualIDs: Set<String>
    private(set) var contextFailures: Set<String> = []
    private(set) var visualPermissionGranted = CGPreflightScreenCaptureAccess()
    private(set) var settingsAppID: String?
    var hasContextWarning: Bool { isRecording && last.map { contextFailures.contains($0.bundleID) } == true }
    private(set) var detailedIDs: Set<String>
    private(set) var contextStatus = "Detailed context is off until enabled per app"
    private var configuredContextApps: [pid_t: String] = [:]
    private var contextTask: Task<Void, Never>?
    private var contextGeneration = UUID()
    private var captureDelay: TimeInterval = 12
    private var lastVisualSample: VisualSample?
    private var lastContextAttempt = Date.distantPast
    let log: RawObservationLog
    private let defaults: UserDefaults
    private var activationToken: NSObjectProtocol?
    private var timer: Timer?
    private var last: RawObservation?
    private var lastEventAt = Date.distantPast
    private var suspended = false
    private var workspaceTokens: [NSObjectProtocol] = []

    var sandboxed: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return true }
        return (SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool) ?? false
    }
    init(defaults: UserDefaults = .standard, log: RawObservationLog? = nil, context: ContextStore? = nil) {
        self.defaults = defaults
        visualIDs = Set(defaults.stringArray(forKey: "visualFallbackIDs") ?? [])
        self.context = context ?? ContextStore()
        detailedIDs = Set(defaults.stringArray(forKey: "detailedContextIDs") ?? [])
        intentNote = defaults.string(forKey: "currentIntentNote") ?? ""
        self.log = log ?? RawObservationLog()
        approvedIDs = Set(defaults.stringArray(forKey: "approvedApplicationIDs") ?? [])
        isPaused = defaults.bool(forKey: "observationPaused")
    }
    func start() {
        guard activationToken == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        activationToken = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.cancelContext(); self?.log.endSession(); self?.suspended = true; self?.last = nil; self?.isRecording = false; self?.setStatus(.sleeping, "Mac asleep · Observation suspended") }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.suspended = false; self?.sample() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        sample()
    }
    func stop() {
        cancelContext()
        context.flush()
        let center = NSWorkspace.shared.notificationCenter
        if let activationToken { center.removeObserver(activationToken) }
        workspaceTokens.forEach { center.removeObserver($0) }
        workspaceTokens.removeAll(); activationToken = nil
        log.endSession()
        timer?.invalidate(); timer = nil; last = nil; isRecording = false
    }
    func togglePause() {
        cancelContext()
        log.endSession()
        isPaused.toggle(); defaults.set(isPaused, forKey: "observationPaused")
        last = nil; sample()
    }
    func approve(_ id: String, enabled: Bool) {
        cancelContext()
        if !enabled { visualIDs.remove(id); defaults.set(visualIDs.sorted(), forKey: "visualFallbackIDs"); contextFailures.remove(id); detailedIDs.remove(id); defaults.set(detailedIDs.sorted(), forKey: "detailedContextIDs") }
        log.endSession()
        if enabled { approvedIDs.insert(id) } else { approvedIDs.remove(id) }
        defaults.set(approvedIDs.sorted(), forKey: "approvedApplicationIDs")
        last = nil; sample()
    }
    func setIntentNote(_ note: String) {
        log.endSession()
        intentNote = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        defaults.set(intentNote, forKey: "currentIntentNote")
        last = nil
        sample()
    }
    func mayObserve(_ id: String) -> Bool {
        !isPaused && !suspended && approvedIDs.contains(id) && id != Bundle.main.bundleIdentifier
    }
    func requestWindowPermission() {
        guard !sandboxed else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        sample()
    }
    private func sample() {
        visualPermissionGranted = CGPreflightScreenCaptureAccess()
        accessibilityGranted = !sandboxed && AXIsProcessTrusted()
        windowPermission = sandboxed ? "Window titles unavailable in this sandboxed build" :
            (accessibilityGranted ? "Accessibility granted · Window titles enabled" : "Accessibility permission required for window titles")
        guard !isPaused, !suspended else { isRecording = false; setStatus(isPaused ? .paused : .sleeping, isPaused ? "Observation paused" : "Mac asleep · Observation suspended"); return }
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier, mayObserve(id) else {
            cancelContext(); log.endSession(); last = nil; isRecording = false
            setStatus(approvedIDs.isEmpty ? .choosing : .waiting, approvedIDs.isEmpty ? "Choose apps to observe" : "Waiting for an approved app")
            return
        }
        let metadata = windowMetadata(pid: app.processIdentifier)
        let event = RawObservation(bundleID: id, applicationName: app.localizedName ?? id,
                                   processID: app.processIdentifier, windowTitle: metadata.0, windowStatus: metadata.1)
        // The user may switch apps or revoke permission while an AX request is in flight.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              mayObserve(id) else { log.endSession(); last = nil; isRecording = false; return }
        guard metadata.0 == nil || AXIsProcessTrusted() else { log.endSession(); last = nil; isRecording = false; return }
        isRecording = true
        if last?.bundleID != id || last?.windowTitle != metadata.0 { cancelContext() }
        captureContextIfNeeded(app: app, id: id, title: metadata.0)
        if log.events.last?.id != last?.id || last?.bundleID != id || last?.processID != event.processID || last?.windowTitle != event.windowTitle || last?.windowStatus != event.windowStatus {
            setStatus(last?.bundleID == id ? .windowChanged : .switched, last?.bundleID == id ? "Window changed in \(event.applicationName)" : "Switched to \(event.applicationName)")
            log.append(event); last = event; lastEventAt = Date()
        } else {
            log.confirmActivity()
            if Date().timeIntervalSince(lastEventAt) > 4 {
                if log.warning != nil { setStatus(.saveWarning, "Activity log needs attention!") }
                else if !accessibilityGranted { setStatus(.appOnly, "Recording app only · Titles off") }
                else if event.windowTitle == nil { setStatus(.titleUnavailable, "Recording app · No window title") }
                else { setStatus(.recording, "Recording app activity...") }
            }
        }
    }
    func mayCaptureContext(_ id: String) -> Bool {
        mayObserve(id) && detailedIDs.contains(id)
    }
    func enableDetailedContext(_ id: String, enabled: Bool) {
        cancelContext()
        if enabled && approvedIDs.contains(id) { detailedIDs.insert(id) } else { detailedIDs.remove(id); visualIDs.remove(id); contextFailures.remove(id); defaults.set(visualIDs.sorted(), forKey: "visualFallbackIDs") }
        defaults.set(detailedIDs.sorted(), forKey: "detailedContextIDs")
        contextStatus = detailedIDs.isEmpty ? "Detailed context is off" : "Waiting for an approved app with detailed context enabled"
    }
    func openContextSettings() {
        settingsAppID = last?.bundleID
        contextSettingsPresented = true
    }
    func enableVisualFallback(_ id: String, enabled: Bool) {
        cancelContext()
        if enabled && approvedIDs.contains(id) && detailedIDs.contains(id) { visualIDs.insert(id) } else { visualIDs.remove(id) }
        defaults.set(visualIDs.sorted(), forKey: "visualFallbackIDs")
    }
    func requestVisualPermission() {
        _ = CGRequestScreenCaptureAccess()
        visualPermissionGranted = CGPreflightScreenCaptureAccess()
    }
    func mayCaptureVisual(_ id: String) -> Bool { mayCaptureContext(id) && visualIDs.contains(id) }
    func clearContext() { cancelContext(); context.clear(); contextStatus = "Context history cleared" }
    private func cancelContext() {
        contextTask?.cancel(); contextTask = nil; contextGeneration = UUID()
        lastContextAttempt = .distantPast
        captureDelay = 12
        lastVisualSample = nil
        contextStatus = "Context capture inactive"
    }
    private func captureContextIfNeeded(app: NSRunningApplication, id: String, title: String?) {
        guard mayCaptureContext(id), accessibilityGranted, !sandboxed else { return }
        guard contextTask == nil, Date().timeIntervalSince(lastContextAttempt) >= captureDelay else { return }
        lastContextAttempt = Date()
        let generation = UUID()
        contextGeneration = generation
        let pid = app.processIdentifier
        let name = app.localizedName ?? id
        let requestSupport = configuredContextApps[pid] != id
        configuredContextApps[pid] = id
        contextStatus = "Reading exposed text from \(name)…"
        contextTask = Task.detached(priority: .utility) { [weak self] in
            let result = ContextCapture.read(pid: pid, bundleID: id, requestAppSupport: requestSupport)
            guard !Task.isCancelled else { return }
            await self?.finishContext(result, id: id, name: name, pid: pid, title: title, generation: generation)
        }
    }
    private func finishContext(_ accessibilityResult: (text: String, status: String), id: String, name: String,
                               pid: pid_t, title: String?, generation: UUID) async {
        guard contextGeneration == generation else { return }
        defer { if contextGeneration == generation { contextTask = nil } }
        guard mayCaptureContext(id), !sandboxed, AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              windowMetadata(pid: pid).0 == title else { contextStatus = "Capture discarded · App, window, or permission changed"; return }
        var result = accessibilityResult
        var source = "accessibility"
        if result.text.isEmpty, !result.status.hasPrefix("Secure field"), mayCaptureVisual(id) {
            visualPermissionGranted = CGPreflightScreenCaptureAccess()
            if visualPermissionGranted, let target = VisualWindowCapture.target(pid: pid) {
                contextStatus = "Reading this window with local OCR…"
                let previousVisual = lastVisualSample
                let visual = Task.detached(priority: .utility) { [weak self] in
                    await VisualWindowCapture.read(target: target, previous: previousVisual) { [weak self] in
                        await self?.visualCaptureAllowed(id: id, target: target, generation: generation) ?? false
                    }
                }
                let captured = await withTaskCancellationHandler(operation: { await visual.value }, onCancel: { visual.cancel() })
                guard contextGeneration == generation else { return }
                lastVisualSample = captured.sample
                result = (captured.text, captured.status)
                source = "windowOCR"
            } else { result.status = visualPermissionGranted ? "Focused window unavailable or secure field focused" : "Enable Screen Recording permission for window-only fallback" }
        }
        guard contextGeneration == generation, mayCaptureContext(id), AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              windowMetadata(pid: pid).0 == title else { return }
        if source == "windowOCR" {
            result.text = ContextReduction.clean(result.text)
            if result.text.isEmpty { result.status = "No meaningful text after local filtering" }
        }
        if result.text.isEmpty { contextFailures.insert(id) } else { contextFailures.remove(id) }
        let changed = context.append(ContextSnapshot(bundleID: id, applicationName: name, windowTitle: title,
                                       text: result.text, status: result.status, source: source))
        captureDelay = ContextReduction.nextDelay(current: captureDelay, changed: changed)
        contextStatus = result.status
    }
    private func visualCaptureAllowed(id: String, target: VisualWindowTarget, generation: UUID) -> Bool {
        guard contextGeneration == generation, mayCaptureVisual(id), AXIsProcessTrusted(), CGPreflightScreenCaptureAccess(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
              let current = VisualWindowCapture.target(pid: target.pid) else { return false }
        return current.windowID == target.windowID && current.frame == target.frame && current.title == target.title
    }
    private func setStatus(_ kind: ObservationStatus, _ message: String) {
        statusKind = kind; status = message
    }
    private func windowMetadata(pid: pid_t) -> (String?, String) {
        guard !sandboxed else { return (nil, "sandboxRestricted") }
        guard AXIsProcessTrusted() else { return (nil, "permissionRequired") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, "windowUnavailable") }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, 0.2)
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success else { return (nil, "titleUnavailable") }
        guard let title = title as? String, !title.isEmpty else { return (nil, "titleUnavailable") }
        return (title, "available")
    }
}
