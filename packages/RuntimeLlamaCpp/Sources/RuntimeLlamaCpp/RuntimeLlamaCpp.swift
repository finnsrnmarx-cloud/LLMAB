import Foundation
import LLMCore

public enum RuntimeLlamaCpp {
    public static let id = "llamacpp"
    /// Default endpoint for the user's `llama-server` install. Override by
    /// passing a custom URL to `LlamaCppRuntime(endpoint:)`.
    public static let defaultEndpoint = URL(string: "http://127.0.0.1:8080")!
}

/// LLMRuntime for `llama-server` (llama.cpp's OpenAI-compatible server).
///
/// Discovery works via:
///   - A reachability probe on the endpoint (`GET /v1/models`).
///   - Listing models by hitting `/v1/models` which llama-server implements
///     OpenAI-style.
///
/// v1 supports text-only chat via `/v1/chat/completions` SSE streaming.
/// Image-in and native tool-use land in a follow-up.
public final class LlamaCppRuntime: LLMRuntime, @unchecked Sendable {

    public let id = RuntimeLlamaCpp.id
    public let displayName = "llama.cpp · llama-server"

    private let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL = RuntimeLlamaCpp.defaultEndpoint,
                session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    // MARK: - Availability

    public func isAvailable() async -> Bool {
        var req = URLRequest(url: endpoint.appendingPathComponent("/v1/models"))
        req.timeoutInterval = 1.5
        do {
            let (_, resp) = try await session.data(for: req)
            return (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    // MARK: - Discovery

    public func discoverModels() async throws -> [ModelInfo] {
        let url = endpoint.appendingPathComponent("/v1/models")
        let (data, resp) = try await session.data(for: URLRequest(url: url))
        guard let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw LLMRuntimeError.badResponse("unexpected /v1/models response")
        }
        struct ModelsResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map { m in
            let (family, variant) = Self.parseFamily(from: m.id)
            return ModelInfo(
                id: "\(RuntimeLlamaCpp.id):\(m.id)",
                rawName: m.id,
                displayName: Self.humanize(m.id),
                runtimeId: RuntimeLlamaCpp.id,
                family: family,
                variant: variant
            )
        }
    }

    // MARK: - Chat (SSE)

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream<ChatChunk, Error> { continuation in
            let task = Task {
                do {
                    try await self.streamChat(request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamChat(_ request: ChatRequest,
                            continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) async throws {
        struct BodyMessage: Encodable {
            let role: String
            let content: String
        }
        struct Body: Encodable {
            let model: String
            let messages: [BodyMessage]
            let stream: Bool
            let temperature: Double?
            let top_p: Double?
            let max_tokens: Int?
        }

        let modelName = request.modelId.hasPrefix("\(RuntimeLlamaCpp.id):")
            ? String(request.modelId.dropFirst(RuntimeLlamaCpp.id.count + 1))
            : request.modelId

        let messages = request.messages.map {
            BodyMessage(role: $0.role.rawValue, content: $0.textContent)
        }
        let body = Body(
            model: modelName,
            messages: messages,
            stream: request.stream,
            temperature: request.sampling.temperature,
            top_p: request.sampling.topP,
            max_tokens: request.sampling.maxTokens
        )

        var req = URLRequest(url: endpoint.appendingPathComponent("/v1/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            var collected = Data()
            for try await b in bytes { collected.append(b) }
            let s = String(data: collected, encoding: .utf8) ?? "<binary>"
            throw LLMRuntimeError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: s)
        }

        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta?
                let finish_reason: String?
            }
            let choices: [Choice]
        }

        let decoder = JSONDecoder()
        for try await line in bytes.lines {
            if Task.isCancelled {
                continuation.finish(throwing: LLMRuntimeError.cancelled)
                return
            }
            // SSE frames start with "data: "
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" {
                continuation.yield(.finish(reason: .stop, usage: nil))
                break
            }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? decoder.decode(Chunk.self, from: data),
                  let choice = chunk.choices.first else { continue }
            if let text = choice.delta?.content, !text.isEmpty {
                continuation.yield(.text(text))
            }
            if let reason = choice.finish_reason {
                continuation.yield(.finish(
                    reason: ChatChunk.FinishReason(rawValue: reason) ?? .stop,
                    usage: nil
                ))
            }
        }
        continuation.finish()
    }

    // MARK: - Helpers

    static func parseFamily(from id: String) -> (family: String, variant: String?) {
        // Common shapes: "llama-3.1-8b", "gemma-4-e4b", "mistral-7b".
        let lowered = id.lowercased()
        if lowered.contains("gemma-4") { return ("gemma-4", variant(from: lowered)) }
        if lowered.contains("gemma-3") { return ("gemma-3", variant(from: lowered)) }
        if lowered.contains("llama-3") { return ("llama-3", variant(from: lowered)) }
        if lowered.contains("qwen-3")  { return ("qwen-3",  variant(from: lowered)) }
        return (lowered, nil)
    }

    private static func variant(from id: String) -> String? {
        // Extract the first of e2b, e4b, 26b, 31b, 8b, 70b, … found in the id.
        let knownTokens = ["e2b", "e4b", "e8b", "2b", "4b", "7b", "8b",
                           "13b", "26b", "27b", "31b", "70b"]
        for token in knownTokens {
            if id.contains(token) { return token }
        }
        return nil
    }

    static func humanize(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
