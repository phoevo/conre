import Foundation
import Observation

@MainActor @Observable
final class SummaryController {
    private(set) var result: ActivitySummary?
    private(set) var isGenerating = false
    private(set) var error: String?
    private let url: URL
    private var writable = true
    private var generation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    init(url: URL = URL.applicationSupportDirectory.appending(path: "Conre/activity-summary.json")) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { result = try JSONDecoder().decode(ActivitySummary?.self, from: Data(contentsOf: url)) }
        catch { writable = false; self.error = "Saved summary unreadable. Original file preserved; new summaries stay in memory." }
    }
    func generate(_ input: SummaryInput, using service: any ActivitySummarizing, completion: ((Bool) -> Void)? = nil) {
        cancel()
        guard !input.evidence.isEmpty else { error = SummaryFailure.empty.localizedDescription; return }
        error = nil; isGenerating = true
        let token = generation
        task = Task { [weak self] in
            do {
                let draft = try await service.summarize(input)
                try Task.checkCancellation()
                let validated = try ActivitySummary.validate(draft, input: input)
                guard let self, self.generation == token else { return }
                self.result = validated; self.isGenerating = false; self.task = nil
                self.persist(); completion?(true)
            } catch {
                guard let self, self.generation == token else { return }
                self.isGenerating = false; self.task = nil
                if !(error is CancellationError) {
                    // Framework errors can include input text; do not echo them into the interface/log.
                    self.error = (error as? SummaryFailure)?.localizedDescription ?? "Could not summarize this context. Try a shorter period; observations are unchanged."
                }
                completion?(false)
            }
        }
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; isGenerating = false }
    func clear() { cancel(); result = nil; persist() }
    private func persist() {
        guard writable else { error = "Original unreadable summary preserved; changes stay in memory."; return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(result)
            try data.write(to: url, options: .atomic)
        } catch { self.error = "Could not save the summary. It remains available during this run." }
    }
}
