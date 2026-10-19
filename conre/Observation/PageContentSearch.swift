import Foundation

/// Locate page content without collecting browser chrome while searching.
enum PageContentSearch {
    nonisolated static func find<Node>(window: Node, focused: Node?,
                                      role: (Node) -> String, parent: (Node) -> Node?,
                                      children: (Node) -> [Node], hidden: (Node) -> Bool,
                                      equal: (Node, Node) -> Bool,
                                      canContinue: () -> Bool) -> Node? {
        // Prefer the focused page, but only if its ancestor chain reaches this window.
        if var node = focused {
            var candidate: Node?
            for _ in 0..<24 {
                guard canContinue() else { return nil }
                if hidden(node) { break }
                if role(node) == "AXWebArea" { candidate = node }
                if equal(node, window) { if let candidate { return candidate }; break }
                guard let next = parent(node) else { break }
                node = next
            }
        }
        var queue = [window]
        var index = 0
        var seen: [Node] = []
        while index < queue.count, seen.count < 200, canContinue() {
            let node = queue[index]; index += 1
            if seen.contains(where: { equal($0, node) }) { continue }
            seen.append(node)
            guard !hidden(node) else { continue }
            let kind = role(node)
            if kind == "AXWebArea" { return node }
            // Toolbars include bookmarks/address-bar suggestions, never page content.
            if ["AXToolbar", "AXMenuBar", "AXMenu", "AXMenuItem", "AXTextField", "AXComboBox", "AXSecureTextField"].contains(kind) { continue }
            queue.append(contentsOf: children(node).prefix(min(60, max(0, 1000 - queue.count))))
        }
        return nil
    }
}

extension PageContentSearch {
    /// Prefer semantic page content over sidebar navigation. Searches only inside the page root.
    nonisolated static func contentRegion<Node>(root: Node, focused: Node?,
                                               role: (Node) -> String, label: (Node) -> String,
                                               parent: (Node) -> Node?, children: (Node) -> [Node],
                                               equal: (Node, Node) -> Bool,
                                               canContinue: () -> Bool) -> Node {
        func isContent(_ node: Node) -> Bool {
            let kind = role(node)
            let name = label(node).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return kind == "AXLandmarkMain" ||
                (["AXGroup", "AXScrollArea"].contains(kind) && ["conversation", "main", "main content"].contains(name))
        }
        if var node = focused {
            var candidate: Node?
            for _ in 0..<40 {
                guard canContinue() else { return root }
                if isContent(node), candidate == nil { candidate = node }
                if equal(node, root) { if let candidate { return candidate }; break }
                guard let next = parent(node) else { break }
                node = next
            }
        }
        var queue = [root]
        var index = 0
        var seen: [Node] = []
        while index < queue.count, seen.count < 200, canContinue() {
            let node = queue[index]; index += 1
            if seen.contains(where: { equal($0, node) }) { continue }
            seen.append(node)
            if isContent(node) { return node }
            if ["AXToolbar", "AXMenu", "AXMenuBar", "AXButton", "AXTextField", "AXTextArea", "AXSecureTextField"].contains(role(node)) { continue }
            queue.append(contentsOf: children(node).prefix(min(60, max(0, 1000 - queue.count))))
        }
        return root
    }
}

extension PageContentSearch {
    nonisolated static func editorRegion<Node>(window: Node, focused: Node?, role: (Node) -> String,
                                              label: (Node) -> String, parent: (Node) -> Node?, children: (Node) -> [Node],
                                              equal: (Node, Node) -> Bool, canContinue: () -> Bool) -> Node {
        if var node = focused {
            var candidate: Node?
            for _ in 0..<40 {
                guard canContinue() else { return window }
                if role(node) == "AXTextArea", candidate == nil { candidate = node }
                if equal(node, window) { if let candidate { return candidate }; break }
                guard let next = parent(node) else { break }; node = next
            }
        }
        var queue = [window]; var index = 0
        while index < queue.count, index < 120, canContinue() {
            let node = queue[index]; index += 1
            let kind = role(node)
            if kind == "AXTextArea", label(node).localizedCaseInsensitiveContains("editor") { return node }
            if ["AXToolbar", "AXTextField", "AXSecureTextField", "AXMenu"].contains(kind) { continue }
            queue.append(contentsOf: children(node).prefix(min(40, max(0, 600 - queue.count))))
        }
        return window
    }
}
