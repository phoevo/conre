import Foundation

protocol SummaryTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

private final class NoSummaryRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct OpenAISummaryTransport: SummaryTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 90
        let session = URLSession(configuration: config, delegate: NoSummaryRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // Bound the response before decoding or retaining a potentially large body.
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw SummaryFailure.invalidResult }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 200_000 else { throw SummaryFailure.invalidResult }
            data.append(byte)
        }
        return (data, response)
    }
}

struct OpenAIActivitySummarizer: ActivitySummarizing {
    static let model = "gpt-4.1-mini"
    let key: String
    var transport: any SummaryTransport = OpenAISummaryTransport()
    static func request(input: SummaryInput, key: String) throws -> URLRequest {
        let node: [String: Any] = ["type": "object", "additionalProperties": false,
            "properties": ["id": ["type": "string"], "parentID": ["type": ["string", "null"]], "title": ["type": "string"],
                           "evidenceIDs": ["type": "array", "items": ["type": "string", "enum": input.evidence.map(\.id)]]],
            "required": ["id", "parentID", "title", "evidenceIDs"]]
        let schema: [String: Any] = ["type": "object", "additionalProperties": false,
            "properties": ["summary": ["type": "string", "description": "One conversational sentence starting with You, ideally 20–30 words, never more than 35; main activity and one supporting detail only."], "nodes": ["type": "array", "items": node]], "required": ["summary", "nodes"]]
        let body: [String: Any] = ["model": model, "store": false, "max_output_tokens": 2000,
            "instructions": SummaryInstructions.text, "input": "Observed activity data only:\n" + input.payload,
            "text": ["format": ["type": "json_schema", "name": "activity_summary", "strict": true, "schema": schema]]]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    func summarize(_ input: SummaryInput) async throws -> SummaryDraft {
        guard !input.evidence.isEmpty else { throw SummaryFailure.empty }
        let (data, response) = try await transport.send(Self.request(input: input, key: key))
        try Task.checkCancellation()
        switch response.statusCode {
        case 200: break
        case 401, 403: throw SummaryFailure.unavailable("OpenAI could not authorize this request. Check your API key and model access.")
        case 429: throw SummaryFailure.unavailable("OpenAI reported a usage or rate limit. Check your API billing and try again later.")
        default: throw SummaryFailure.unavailable("OpenAI could not complete the request (HTTP \(response.statusCode)). Try again later.")
        }
        return try Self.decode(data)
    }
    static func decode(_ data: Data) throws -> SummaryDraft {
        struct Envelope: Decodable {
            struct Item: Decodable {
                struct Content: Decodable { let type: String; let text: String? }
                let type: String; let content: [Content]?
            }
            let status: String
            let output: [Item]
        }
        let response = try JSONDecoder().decode(Envelope.self, from: data)
        guard response.status == "completed" else { throw SummaryFailure.unavailable("The summary was incomplete. Try again with a shorter period.") }
        let content = response.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        guard !content.contains(where: { $0.type == "refusal" }) else { throw SummaryFailure.unavailable("OpenAI declined to summarize this context. Try a different period.") }
        let text = content.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw SummaryFailure.invalidResult }
        return try JSONDecoder().decode(SummaryDraft.self, from: Data(text.utf8))
    }
}
