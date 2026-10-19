import Foundation
import ApplicationServices

/// These apps may defer their content accessibility tree until a client asks for it.
enum AppAccessibilitySupport {
    nonisolated static func attribute(for bundleID: String) -> String? {
        if ["com.openai.codex", "com.openai.chat", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
            "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "com.tinyspeck.slackmacgap"].contains(bundleID) {
            return "AXManualAccessibility"
        }
        if ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
            "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi",
            "company.thebrowser.Browser", "com.operasoftware.Opera"].contains(bundleID) {
            return "AXEnhancedUserInterface"
        }
        return nil
    }
    nonisolated static func request(pid: pid_t, bundleID: String) -> String? {
        guard let attribute = attribute(for: bundleID) else { return nil }
        guard AXIsProcessTrusted(), !Task.isCancelled else { return "App support request requires Accessibility permission" }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let result = AXUIElementSetAttributeValue(app, attribute as CFString, kCFBooleanTrue)
        return result == .success ? "App accessibility requested" : "App accessibility request unavailable (\(result.rawValue))"
    }
}
