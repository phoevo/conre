import Foundation

struct AutomaticSummaryPolicy {
    struct Change { let id: UUID; let arrivedAt: Date; let characters: Int }
    private(set) var pending: [UUID: Change] = [:]
    private var rawTexts: [UUID: String] = [:]
    private var signatures: [UUID: String] = [:]
    private var previousWords: [String: Set<String>] = [:]
    private(set) var firstChangeAt: Date?
    private(set) var lastChangeAt: Date?
    var lastRequestAt: Date = .distantPast
    var retryAfter: Date = .distantPast
    var requestDates: [Date] = []

    mutating func observe(_ snapshots: [ContextSnapshot], now: Date) {
        let ids = Set(snapshots.map(\.id))
        rawTexts = rawTexts.filter { ids.contains($0.key) }
        signatures = signatures.filter { ids.contains($0.key) }
        pending = pending.filter { ids.contains($0.key) }
        firstChangeAt = pending.values.map(\.arrivedAt).min()
        lastChangeAt = pending.values.map(\.arrivedAt).max()
        for snapshot in snapshots.sorted(by: { $0.timestamp < $1.timestamp }) where !snapshot.text.isEmpty {
            guard rawTexts[snapshot.id] != snapshot.text else { continue }
            rawTexts[snapshot.id] = snapshot.text
            let normalized = snapshot.text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard signatures[snapshot.id] != normalized else { continue }
            signatures[snapshot.id] = normalized
            let key = snapshot.bundleID + "\n" + (snapshot.windowTitle ?? "")
            let words = Set(normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let newWords = words.subtracting(previousWords[key] ?? [])
            previousWords[key] = words
            // Seed comparison state from older history without sending it at launch.
            guard snapshot.latestDate >= now.addingTimeInterval(-900), newWords.count >= 8 else { continue }
            let size = newWords.reduce(0) { $0 + $1.count + 1 }
            guard size >= 60 else { continue }
            pending[snapshot.id] = Change(id: snapshot.id, arrivedAt: now, characters: size)
            firstChangeAt = firstChangeAt ?? now; lastChangeAt = now
        }
    }
    func shouldRequest(now: Date, flush: Bool = false) -> Bool {
        guard let firstChangeAt, let lastChangeAt,
              now >= retryAfter, now.timeIntervalSince(lastRequestAt) >= 120,
              requestDates.filter({ now.timeIntervalSince($0) < 3600 }).count < 12 else { return false }
        let size = pending.values.reduce(0) { $0 + $1.characters }
        let enough = size >= 600 || (pending.count >= 3 && size >= 240)
        let settled = now.timeIntervalSince(lastChangeAt) >= 25
        let waited = now.timeIntervalSince(firstChangeAt) >= 180
        return (enough && (settled || waited)) || ((flush || waited) && size >= 100)
    }
    mutating func started(at date: Date) {
        lastRequestAt = date
        requestDates = requestDates.filter { date.timeIntervalSince($0) < 3600 } + [date]
    }
    mutating func succeeded(through date: Date) {
        pending = pending.filter { $0.value.arrivedAt > date }
        firstChangeAt = pending.values.map(\.arrivedAt).min()
        lastChangeAt = pending.values.map(\.arrivedAt).max()
        retryAfter = .distantPast
    }
    mutating func failed(at date: Date) { retryAfter = date.addingTimeInterval(600) }
    mutating func discardPending() { pending.removeAll(); signatures.removeAll(); rawTexts.removeAll(); previousWords.removeAll(); firstChangeAt = nil; lastChangeAt = nil }
}

struct ReturnFromIdlePolicy {
    private(set) var away = false
    private(set) var lastWorkAt: Date?
    private var awaitingFreshInput = false
    private var lastResumeAt: Date?
    mutating func suspended(now: Date) {
        if !away { lastWorkAt = now }
        away = true; awaitingFreshInput = false
    }
    mutating func resumed(now: Date) -> Bool {
        if let lastResumeAt, now.timeIntervalSince(lastResumeAt) < 30 { return false }
        if !away { lastWorkAt = now }
        away = false; awaitingFreshInput = true; lastResumeAt = now
        return true
    }
    mutating func update(now: Date, idleSeconds: Double, sessionActive: Bool) -> Bool {
        if !sessionActive { suspended(now: now); return false }
        if awaitingFreshInput {
            if idleSeconds < 10 { awaitingFreshInput = false }
            return false
        }
        if idleSeconds >= 180 {
            if !away { lastWorkAt = now.addingTimeInterval(-max(0, idleSeconds)); away = true }
            return false
        }
        if away && idleSeconds < 10 { away = false; return true }
        return false
    }
}
