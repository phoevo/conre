import Observation

/// Phase 1 holds intent only. Future collectors must live outside SwiftUI and
/// require explicit application approval before collecting observations.
@MainActor @Observable
final class ActivityObserver {
    private(set) var isPaused = false
    func togglePause() { isPaused.toggle() }
}
