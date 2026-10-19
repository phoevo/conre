import Foundation

struct ActivitySession: Identifiable {
    let id: UUID
    let applicationName: String
    let bundleID: String
    let intentNote: String?
    var observations: [RawObservation]
    var startedAt: Date { observations[0].timestamp }
    var endedAt: Date? { observations.last?.observedUntil }
    var knownDuration: TimeInterval? {
        guard observations.allSatisfy({ $0.observedUntil != nil }) else { return nil }
        return observations.reduce(0) { $0 + max(0, ($1.observedUntil ?? $1.timestamp).timeIntervalSince($1.timestamp)) }
    }
    var titles: [String] {
        observations.reduce(into: []) { result, observation in
            let title = observation.windowTitle ?? "Window title unavailable"
            if result.last != title { result.append(title) }
        }
    }
    static func grouped(_ events: [RawObservation]) -> [ActivitySession] {
        var result: [ActivitySession] = []
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let previous = result.last,
               previous.bundleID == event.bundleID,
               previous.observations.last?.processID == event.processID,
               previous.intentNote == event.intentNote,
               let end = previous.endedAt, abs(end.timeIntervalSince(event.timestamp)) < 0.001 {
                result[result.count - 1].observations.append(event)
            } else {
                result.append(ActivitySession(id: event.id, applicationName: event.applicationName,
                                              bundleID: event.bundleID, intentNote: event.intentNote,
                                              observations: [event]))
            }
        }
        return result
    }
}
