import Foundation

enum ContextReduction {
    nonisolated static func clean(_ text: String) -> String {
        if looksLikeCode(text) { return text }
        let controls: Set<String> = ["Copy", "Copy message", "Share", "Share prompt", "Edit message", "New chat", "Search", "Search...", "Hide sidebar", "Show sidebar", "Regenerate", "More actions", "Rate response", "Dictate", "Start Voice", "ChatGPT can make mistakes. Check important info."]
        return text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !controls.contains($0) }
            .joined(separator: "\n")
    }
    nonisolated static func looksLikeCode(_ text: String) -> Bool {
        ["{", "}", "==", "!=", "=>", "<=", ">=", "func ", "function ", "class ", "import ", "let ", "const ", "def ", "return "]
            .contains(where: { text.contains($0) })
    }
    nonisolated static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    nonisolated static func similarOCR(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs.count >= 200, rhs.count >= 200 else { return false }
        // Small code edits matter: never fuzzy-merge code-shaped text.
        guard !looksLikeCode(lhs), !looksLikeCode(rhs) else { return false }
        let aNumbers = lhs.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        let bNumbers = rhs.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard aNumbers == bNumbers else { return false }
        func shingles(_ value: String) -> Set<String> {
            let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count >= 3 else { return Set(words) }
            return Set((0..<(words.count - 2)).map { words[$0...($0 + 2)].joined(separator: " ") })
        }
        let a = shingles(lhs), b = shingles(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return Double(a.intersection(b).count) / Double(a.union(b).count) >= 0.9
    }
    nonisolated static func nextDelay(current: TimeInterval, changed: Bool) -> TimeInterval {
        changed ? 12 : min(60, max(12, current * 2))
    }
}
