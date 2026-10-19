import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

struct VisualWindowTarget: Sendable {
    let pid: pid_t
    let windowID: CGWindowID?
    let frame: CGRect
    let title: String?
    nonisolated init(pid: pid_t, windowID: CGWindowID?, frame: CGRect, title: String?) {
        self.pid = pid; self.windowID = windowID; self.frame = frame; self.title = title
    }
}

struct VisualSample: Sendable {
    let fingerprint: [UInt8]
    let text: String
    let status: String
    let lastOCRAt: Date
    nonisolated init(fingerprint: [UInt8], text: String, status: String, lastOCRAt: Date) {
        self.fingerprint = fingerprint; self.text = text; self.status = status; self.lastOCRAt = lastOCRAt
    }
}

enum VisualWindowCapture {
    nonisolated static func target(pid: pid_t) -> VisualWindowTarget? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        func value(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(node, name as CFString, &result) == .success else { return nil }
            return result
        }
        if let focused = value(app, "AXFocusedUIElement"), CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let node = unsafeBitCast(focused, to: AXUIElement.self)
            if (value(node, "AXSubrole") as? String) == "AXSecureTextField" || (value(node, "AXRole") as? String) == "AXSecureTextField" { return nil }
        }
        guard let raw = value(app, "AXFocusedWindow"), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, 0.1)
        guard let position = value(window, "AXPosition"), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(window, "AXSize"), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 else { return nil }
        let id = (value(window, "AXWindowNumber") as? NSNumber)?.uint32Value
        return VisualWindowTarget(pid: pid, windowID: id, frame: CGRect(origin: point, size: dimensions), title: value(window, "AXTitle") as? String)
    }
    nonisolated static func matches(_ target: VisualWindowTarget, id: CGWindowID, pid: pid_t, frame: CGRect, title: String?) -> Bool {
        guard pid == target.pid else { return false }
        if let expected = target.windowID { return expected == id }
        // Fail closed on ambiguity; never pick the first window belonging to an app.
        let sameFrame = abs(frame.minX - target.frame.minX) < 2 && abs(frame.minY - target.frame.minY) < 2 &&
            abs(frame.width - target.frame.width) < 2 && abs(frame.height - target.frame.height) < 2
        return sameFrame && (target.title == nil || target.title == title)
    }
    nonisolated static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return String((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n").prefix(6000))
    }
    nonisolated static func fingerprint(_ image: CGImage) -> [UInt8] {
        var rendered = false
        var pixels = [UInt8](repeating: 0, count: 64 * 40)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 64, height: 40, bitsPerComponent: 8,
                                          bytesPerRow: 64, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return }
            rendered = true
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 40))
        }
        return rendered ? pixels : []
    }
    nonisolated static func similarImage(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard !a.isEmpty, a.count == b.count else { return false }
        let changed = zip(a, b).filter { abs(Int($0.0) - Int($0.1)) > 18 }.count
        return Double(changed) / Double(a.count) < 0.005
    }
    nonisolated static func read(target: VisualWindowTarget, previous: VisualSample? = nil, allowed: @escaping @Sendable () async -> Bool) async -> (text: String, status: String, sample: VisualSample?) {
        guard !Task.isCancelled, CGPreflightScreenCaptureAccess(), await allowed() else {
            return ("", "Visual fallback requires Screen Recording permission", nil)
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard !Task.isCancelled, await allowed() else { return ("", "Visual capture cancelled", nil) }
            let candidates = content.windows.filter {
                $0.windowLayer == 0 && matches(target, id: $0.windowID, pid: $0.owningApplication?.processID ?? -1, frame: $0.frame, title: $0.title)
            }
            guard candidates.count == 1, let window = candidates.first else { return ("", "Focused window could not be identified safely", nil) }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = min(2, 2400 / max(window.frame.width, window.frame.height))
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.showsCursor = false
            config.capturesAudio = false
            config.ignoreShadowsSingleWindow = true
            guard !Task.isCancelled, await allowed() else { return ("", "Visual capture cancelled", nil) }
            // A single approved window, no display-wide capture and no image persistence.
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard !Task.isCancelled, await allowed() else { return ("", "Visual capture discarded after app/window change", nil) }
            let pixels = fingerprint(image)
            if let previous, Date().timeIntervalSince(previous.lastOCRAt) < 60,
               similarImage(previous.fingerprint, pixels) {
                return (previous.text, previous.status, previous)
            }
            let rawText = try recognizeText(in: image)
            guard !Task.isCancelled, await allowed() else { return ("", "Visual capture cancelled", nil) }
            let evidence = CaptureEvidence.result(content: rawText.components(separatedBy: "\n"), interface: [],
                                                  windowTitle: target.title, bounded: rawText.count >= 6000, browser: false, nodeCount: 0)
            let status = evidence.text.isEmpty ? "Window OCR found no body text" : "Window-only OCR text captured"
            return (evidence.text, status, VisualSample(fingerprint: pixels, text: evidence.text, status: status, lastOCRAt: Date()))
        } catch { return ("", "Window-only capture unavailable: \(error.localizedDescription)", nil) }
    }
}
