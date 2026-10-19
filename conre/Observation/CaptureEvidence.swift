import Foundation

/// A window title or a collection of control labels is not captured body text.
enum CaptureEvidence {
    nonisolated static func result(content: [String], interface: [String], windowTitle: String?,
                                   bounded: Bool, browser: Bool, nodeCount: Int) -> (text: String, status: String) {
        let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let useful = content.filter {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && value.lowercased() != title
        }
        guard !useful.isEmpty else {
            return ("", "No body text captured · \(nodeCount) elements inspected\(bounded ? " · Limit reached" : "")")
        }
        var seen = Set<String>()
        let text = useful.filter { seen.insert($0).inserted }.joined(separator: "\n")
        return (String(text.prefix(6000)), bounded ? "Partial body text · Limit reached" : browser ? "Page body text captured" : "Exposed body text captured")
    }
}
