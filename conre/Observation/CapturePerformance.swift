import Foundation
import Observation

@MainActor @Observable
final class CapturePerformance {
    let startedAt = Date()
    private(set) var attempts = 0
    private(set) var totalCaptureSeconds: Double = 0
    private(set) var longestCaptureSeconds: Double = 0
    private(set) var ocrRuns = 0
    private(set) var reusedOCR = 0
    private(set) var diskWrites = 0
    private(set) var writtenBytes = 0
    func capture(seconds: Double, ocr: Bool, reused: Bool) {
        attempts += 1; totalCaptureSeconds += seconds
        longestCaptureSeconds = max(longestCaptureSeconds, seconds)
        if ocr { ocrRuns += 1 }; if reused { reusedOCR += 1 }
    }
    func write(bytes: Int) { diskWrites += 1; writtenBytes += bytes }
    var averageSeconds: Double { attempts == 0 ? 0 : totalCaptureSeconds / Double(attempts) }
}
