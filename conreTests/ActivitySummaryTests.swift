import Foundation
import Testing
@testable import conre

@MainActor
struct ActivitySummaryTests {
    private var time: Date { Date(timeIntervalSince1970: 5000) }
    private func snapshot(_ text: String, offset: Double = 0) -> ContextSnapshot {
        ContextSnapshot(timestamp: time.addingTimeInterval(offset), bundleID: "test.editor", applicationName: "Editor", windowTitle: "globals.css", text: text, status: "Captured")
    }
    private func input() -> SummaryInput { SummaryInput.build([snapshot("accent: blue")], since: time.addingTimeInterval(-1), until: time.addingTimeInterval(1)) }
    private func draft(_ input: SummaryInput) -> SummaryDraft {
        SummaryDraft(summary: "You reviewed theme colors in globals.css.", nodes: [
            .init(id: "root", parentID: nil, title: "Theme colors", evidenceIDs: [input.evidence[0].id]),
            .init(id: "child", parentID: "root", title: "Reviewed accent color", evidenceIDs: [input.evidence[0].id])])
    }
    @Test func inputUsesBoundedRecentChangesAndNoEmptyAttempts() {
        let snapshots = [snapshot("old", offset: -500), snapshot("accent: blue"), snapshot("accent: blue\nmuted: gray", offset: 5), snapshot("", offset: 6), snapshot("future", offset: 500)]
        let result = SummaryInput.build(snapshots, since: time.addingTimeInterval(-1), until: time.addingTimeInterval(10))
        #expect(result.evidence.count == 2)
        #expect(result.evidence[1].text == "muted: gray")
        let large = (0..<40).map { snapshot(String(repeating: "x", count: 2000) + "\($0)", offset: Double($0)) }
        let bounded = SummaryInput.build(large, since: time, until: time.addingTimeInterval(100))
        #expect(bounded.evidence.count <= 12)
        #expect(bounded.evidence.reduce(0) { $0 + $1.text.count } <= 9000)
        #expect(bounded.evidence.last?.timestamp == time.addingTimeInterval(39))
        #expect(bounded.evidence.first?.timestamp == time)
    }
    @Test func validatesEvidenceAndBuildsOrderedTree() throws {
        let input = input()
        let result = try ActivitySummary.validate(draft(input), input: input)
        #expect(result.roots.count == 1)
        #expect(result.roots[0].children[0].evidence == input.evidence)
        let invalid = SummaryDraft(summary: "Unsupported", nodes: [.init(id: "bad", parentID: nil, title: "Installed", evidenceIDs: ["invented"])])
        #expect(throws: SummaryFailure.self) { try ActivitySummary.validate(invalid, input: input) }
        let cycle = SummaryDraft(summary: "Cycle", nodes: [.init(id: "a", parentID: "a", title: "Cycle", evidenceIDs: [input.evidence[0].id])])
        #expect(throws: SummaryFailure.self) { try ActivitySummary.validate(cycle, input: input) }
    }
    @Test func rejectsMultipleSentencesAndRepeatedCitations() {
        let input = input()
        let multiple = SummaryDraft(summary: "You reviewed colors. You installed a button.", nodes: draft(input).nodes)
        #expect(throws: SummaryFailure.self) { try ActivitySummary.validate(multiple, input: input) }
        let repeated = SummaryDraft(summary: "Reviewed colors.", nodes: [.init(id: "a", parentID: nil, title: "Colors", evidenceIDs: [input.evidence[0].id, input.evidence[0].id])])
        #expect(throws: SummaryFailure.self) { try ActivitySummary.validate(repeated, input: input) }
    }
    @Test func requestIsTextOnlyBoundedAndNotStored() throws {
        let input = input()
        let request = try OpenAIActivitySummarizer.request(input: input, key: "test-key")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["store"] as? Bool == false)
        #expect(body["tools"] == nil)
        #expect(body["input"] as? String == "Observed activity data only:\n" + input.payload)
        #expect(!String(data: request.httpBody!, encoding: .utf8)!.contains("test-key"))
    }
    @Test func parsesStructuredResponseRejectsRefusalAndIncomplete() throws {
        let encoded = try JSONEncoder().encode(draft(input()))
        let text = String(decoding: encoded, as: UTF8.self)
        let response: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]]
        #expect(try OpenAIActivitySummarizer.decode(JSONSerialization.data(withJSONObject: response)).nodes.count == 2)
        let refusal = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal"}]}]}"#.utf8)
        #expect(throws: SummaryFailure.self) { try OpenAIActivitySummarizer.decode(refusal) }
        #expect(throws: SummaryFailure.self) { try OpenAIActivitySummarizer.decode(Data(#"{"status":"incomplete","output":[]}"#.utf8)) }
    }
    @Test func httpErrorsDoNotEchoProviderBody() async throws {
        let service = OpenAIActivitySummarizer(key: "test", transport: FakeTransport(code: 429, body: Data("private provider error".utf8)))
        do { _ = try await service.summarize(input()); Issue.record("Expected a limit error") }
        catch { #expect(error.localizedDescription.contains("rate limit")); #expect(!error.localizedDescription.contains("private")) }
    }
    @Test func summaryPersistsAndClearSurvivesReload() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = SummaryController(url: url)
        let input = input()
        controller.generate(input, using: FakeSummarizer(draft: draft(input)))
        while controller.isGenerating { await Task.yield() }
        #expect(controller.result?.roots.count == 1)
        #expect(SummaryController(url: url).result?.sentence == controller.result?.sentence)
        controller.clear()
        let reloaded = SummaryController(url: url)
        #expect(reloaded.result == nil)
        #expect(reloaded.error == nil)
    }
    @Test func cancellationDiscardsLateResult() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        let controller = SummaryController(url: url)
        controller.generate(input(), using: SlowSummarizer(draft: draft(input())))
        controller.cancel()
        try await Task.sleep(for: .milliseconds(30))
        #expect(controller.result == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
    @Test func corruptSummaryRemainsUntouched() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        let bytes = Data("unreadable".utf8)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = SummaryController(url: url)
        controller.clear()
        #expect(try Data(contentsOf: url) == bytes)
        #expect(controller.error != nil)
    }
}
private struct FakeTransport: SummaryTransport {
    let code: Int
    let body: Data
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (body, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}
private struct FakeSummarizer: ActivitySummarizing {
    let draft: SummaryDraft
    func summarize(_ input: SummaryInput) async throws -> SummaryDraft { draft }
}
private struct SlowSummarizer: ActivitySummarizing {
    let draft: SummaryDraft
    func summarize(_ input: SummaryInput) async throws -> SummaryDraft {
        try? await Task.sleep(for: .milliseconds(20))
        return draft
    }
}
