import Foundation
import CoreGraphics

enum CaptureHealth: String {
    case captured = "Context captured", partial = "Partial context", permission = "Permission needed"
    case unavailable = "No text found", waiting = "Waiting for context", paused = "Capture paused", activity = "App activity only"
    var symbol: String {
        switch self {
        case .captured: "checkmark.circle.fill"
        case .partial: "text.viewfinder"
        case .permission: "lock.trianglebadge.exclamationmark"
        case .unavailable: "exclamationmark.triangle.fill"
        case .waiting: "clock"
        case .paused: "pause.circle"
        case .activity: "app"
        }
    }
    var needsAttention: Bool { self == .permission || self == .unavailable }
    static func classify(text: String, status: String) -> Self {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return status.localizedCaseInsensitiveContains("partial") || status.localizedCaseInsensitiveContains("limit reached") ? .partial : .captured
        }
        if status.localizedCaseInsensitiveContains("secure field") || status.localizedCaseInsensitiveContains("cancelled") { return .paused }
        if status.localizedCaseInsensitiveContains("permission") { return .permission }
        return .unavailable
    }
}

extension ContextSnapshot {
    var health: CaptureHealth { CaptureHealth.classify(text: text, status: status) }
    var latestDate: Date { lastSeenAt ?? timestamp }
}

struct ContextChange: Identifiable {
    let snapshot: ContextSnapshot
    let added: [String]
    let removedCount: Int
    let first: Bool
    var id: UUID { snapshot.id }
    var headline: String { first ? "Context first seen" : added.isEmpty ? "Text no longer visible" : "New text observed" }
    static func build(_ snapshots: [ContextSnapshot]) -> [ContextChange] {
        struct Key: Hashable { let app: String; let window: String? }
        var previous: [Key: [String]] = [:]
        var result: [ContextChange] = []
        for snapshot in snapshots.sorted(by: { $0.timestamp < $1.timestamp }) where !snapshot.text.isEmpty {
            let key = Key(app: snapshot.bundleID, window: snapshot.windowTitle)
            let lines = snapshot.text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let old = previous[key]
            previous[key] = lines
            guard let old else { result.append(Self(snapshot: snapshot, added: lines, removedCount: 0, first: true)); continue }
            let difference = lines.difference(from: old)
            var added: [(Int, String)] = []
            var removed = 0
            for change in difference {
                switch change {
                case .insert(let index, let line, _): added.append((index, line))
                case .remove: removed += 1
                }
            }
            if !added.isEmpty || removed > 0 {
                result.append(Self(snapshot: snapshot, added: added.sorted { $0.0 < $1.0 }.map(\.1), removedCount: removed, first: false))
            }
        }
        return result.reversed()
    }
}

struct OCRTextLine {
    let text: String
    let bounds: CGRect
    let confidence: Float
}

enum OCRContentFilter {
    nonisolated static func select(_ lines: [OCRTextLine]) -> [OCRTextLine] {
        // Infer a reading column only when several long lines agree. Otherwise retain the evidence.
        let anchors = lines.filter { $0.confidence >= 0.45 && $0.text.count >= 40 && $0.bounds.width >= 0.25 && $0.bounds.minX >= 0.12 }
        guard anchors.count >= 3 else { return lines }
        let left = max(0.12, min(0.45, (anchors.map(\.bounds.minX).min() ?? 0) - 0.04))
        return lines.filter { line in
            if line.bounds.maxX < left { return false }
            if line.bounds.midY > 0.95 && line.text.count < 35 { return false }
            return true
        }
    }
}

enum AppCaptureMode: String, CaseIterable {
    case off = "Off", activity = "App activity", text = "Detailed text", visual = "Text + visual fallback"
}
