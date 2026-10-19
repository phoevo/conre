import Foundation
import ApplicationServices

/// Reads exposed text, never pixels or input events. Runs off the UI thread.
enum ContextCapture {
    nonisolated static func read(pid: pid_t, bundleID: String = "", requestAppSupport: Bool = false) -> (text: String, status: String) {
        // Request the renderer's exposed text tree, never OS permission or UI actions.
        let supportStatus = requestAppSupport ? AppAccessibilitySupport.request(pid: pid, bundleID: bundleID) : nil
        // Page discovery and extraction have separate deadlines. A cold renderer
        // must not consume the entire text budget while its tree is being found.
        var deadline = Date().addingTimeInterval(3)
        var failures: [Int32: Int] = [:]
        var requestCount = 0
        var roleCounts: [String: Int] = [:]
        func diagnostics() -> String {
            let errors = failures.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
            let roles = roleCounts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
            return "AX requests \(requestCount); errors [\(errors)]; roles [\(roles)]"
        }
        let app = AXUIElementCreateApplication(pid)
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard Date() < deadline, !Task.isCancelled else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.05)
            var value: CFTypeRef?
            requestCount += 1
            let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            guard result == .success else { failures[result.rawValue, default: 0] += 1; return nil }
            if name == "AXRole", let role = value as? String { roleCounts[role, default: 0] += 1 }
            return value
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
        func secure(_ node: AXUIElement) -> Bool {
            let role = attribute(node, "AXRole") as? String ?? ""
            let subrole = attribute(node, "AXSubrole") as? String ?? ""
            return role == "AXSecureTextField" || subrole == "AXSecureTextField"
        }
        if let focused = element(attribute(app, "AXFocusedUIElement")), secure(focused) {
            return ("", "Secure field focused · Capture skipped")
        }
        guard let window = element(attribute(app, "AXFocusedWindow")) else {
            return ("", "App did not expose a focused window")
        }
        let windowTitle = attribute(window, "AXTitle") as? String
        let browser = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
                       "com.apple.Safari", "com.apple.SafariTechnologyPreview", "org.mozilla.firefox",
                       "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly", "com.microsoft.edgemac",
                       "com.brave.Browser", "com.vivaldi.Vivaldi", "company.thebrowser.Browser",
                       "com.operasoftware.Opera"].contains(bundleID)
        let focused = element(attribute(app, "AXFocusedUIElement"))
        let root: AXUIElement
        if browser {
            guard let page = PageContentSearch.find(window: window, focused: focused,
                role: { attribute($0, "AXRole") as? String ?? "" },
                parent: { element(attribute($0, "AXParent")) },
                children: { (attribute($0, "AXChildren") as? [AXUIElement]) ?? [] },
                hidden: { (attribute($0, "AXHidden") as? Bool) == true },
                equal: { CFEqual($0, $1) },
                canContinue: { Date() < deadline && !Task.isCancelled }) else {
                return ("", "Page text unavailable · \(Date() >= deadline ? "Discovery timed out" : "No exposed page root") · \(diagnostics())\(supportStatus.map { " · " + $0 } ?? "")")
            }
            root = PageContentSearch.contentRegion(root: page, focused: focused,
                role: { attribute($0, "AXRole") as? String ?? "" },
                label: { (attribute($0, "AXTitle") as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (attribute($0, "AXDescription") as? String) ?? "" },
                parent: { element(attribute($0, "AXParent")) },
                children: { attribute($0, "AXChildren") as? [AXUIElement] ?? [] },
                equal: { CFEqual($0, $1) },
                canContinue: { Date() < deadline && !Task.isCancelled })
        } else { root = window }
        deadline = Date().addingTimeInterval(2)
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        if !browser, let focused { stack.append((focused, 0)) }
        var visited: [AXUIElement] = []
        var snippets: [String] = []
        var contentSnippets: [String] = []
        var seenText = Set<String>()
        var length = 0
        var depthLimited = false
        var childrenLimited = false
        while let (node, depth) = stack.popLast(), visited.count < 160, length < 6000,
              Date() < deadline, !Task.isCancelled {
            if visited.contains(where: { CFEqual($0, node) }) { continue }
            visited.append(node)
            let role = attribute(node, "AXRole") as? String ?? ""
            let subrole = attribute(node, "AXSubrole") as? String ?? ""
            guard role != "AXSecureTextField", subrole != "AXSecureTextField",
                  (attribute(node, "AXHidden") as? Bool) != true else { continue }
            // Input fields are deliberately excluded, including their descendants.
            if ["AXTextField", "AXComboBox", "AXToolbar", "AXMenuBar", "AXMenu"].contains(role) { continue }
            var values: [String] = []
            if role == "AXTextArea" {
                // AXValue can contain an entire document. Request only the exposed visible range.
                if let range = attribute(node, "AXVisibleCharacterRange"), CFGetTypeID(range) == AXValueGetTypeID() {
                    var visible = CFRange()
                    if AXValueGetValue(unsafeBitCast(range, to: AXValue.self), .cfRange, &visible), visible.location >= 0, visible.length > 0 {
                        visible.length = min(visible.length, 2000)
                        if let bounded = AXValueCreate(.cfRange, &visible) {
                            var text: CFTypeRef?
                            if AXUIElementCopyParameterizedAttributeValue(node, "AXStringForRange" as CFString, bounded, &text) == .success,
                               let text = text as? String { values.append(text) }
                        }
                    }
                } else {
                    // Some native read-only message views expose no visible-range attribute.
                    // Never use this fallback for editable fields or draft composers.
                    var settable = DarwinBoolean(false)
                    if AXUIElementIsAttributeSettable(node, "AXValue" as CFString, &settable) == .success,
                       !settable.boolValue,
                       let text = attribute(node, "AXValue") as? String {
                        values.append(String(text.prefix(2000)))
                    }
                }
            } else if ["AXStaticText", "AXHeading", "AXLink", "AXButton", "AXWindow"].contains(role) {
                if let text = attribute(node, "AXTitle") as? String { values.append(text) }
                if ["AXStaticText", "AXHeading"].contains(role) {
                    if let text = attribute(node, "AXValue") as? String { values.append(text) }
                    if values.isEmpty, let text = attribute(node, "AXDescription") as? String { values.append(text) }
                }
            }
            for value in values {
                let text = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(min(2000, 6000 - length)))
                if !text.isEmpty, seenText.insert(text).inserted {
                    snippets.append(text); length += text.count
                    if ["AXStaticText", "AXHeading", "AXTextArea"].contains(role) { contentSnippets.append(text) }
                }
            }
            guard role != "AXTextArea", role != "AXButton" else { continue }
            let children = attribute(node, "AXChildren") as? [AXUIElement] ?? []
            guard depth < 32 else { if !children.isEmpty { depthLimited = true }; continue }
            if children.count > 120 { childrenLimited = true }
            stack.append(contentsOf: children.prefix(120).reversed().map { ($0, depth + 1) })
        }
        let bounded = visited.count >= 160 || length >= 6000 || Date() >= deadline || depthLimited || childrenLimited
        let result = CaptureEvidence.result(content: contentSnippets, interface: snippets,
                                      windowTitle: windowTitle,
                                      bounded: bounded, browser: browser, nodeCount: visited.count)
        if result.text.isEmpty {
            return (result.text, "\(result.status) · \(diagnostics())\(supportStatus.map { " · " + $0 } ?? "")")
        }
        return result
    }
}
