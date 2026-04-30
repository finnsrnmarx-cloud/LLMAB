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
/// Supports OpenAI-compatible SSE streaming via `/v1/chat/completions`,
/// including text, image parts, and streamed tool calls when the served model
/// exposes them.
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
        var req = URLRequest(url: endpoint.appendingPathComponent("/v1/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Self.wireBodyData(for: request)

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
                struct Delta: Decodable {
                    let content: String?
                    let tool_calls: [ToolCallDelta]?
                }
                struct ToolCallDelta: Decodable {
                    struct Function: Decodable {
                        let name: String?
                        let arguments: String?
                    }
                    let index: Int?
                    let id: String?
                    let function: Function?
                }
                let delta: Delta?
                let finish_reason: String?
            }
            let choices: [Choice]
        }

        struct ToolCallBuffer {
            var id: String?
            var name: String?
            var arguments = ""
        }

        var toolBuffers: [Int: ToolCallBuffer] = [:]
        var didEmitToolCalls = false
        var didYieldFinish = false

        func emitToolCalls() {
            guard !didEmitToolCalls else { return }
            didEmitToolCalls = true
            for key in toolBuffers.keys.sorted() {
                guard let buffer = toolBuffers[key],
                      let name = buffer.name else { continue }
                let arguments = buffer.arguments.isEmpty ? "{}" : buffer.arguments
                continuation.yield(.toolCall(ToolCall(
                    id: buffer.id ?? UUID().uuidString,
                    toolId: name,
                    argumentsJSON: Data(arguments.utf8)
                )))
            }
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
                if !didYieldFinish {
                    continuation.yield(.finish(reason: .stop, usage: nil))
                }
                break
            }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? decoder.decode(Chunk.self, from: data),
                  let choice = chunk.choices.first else { continue }
            if let text = choice.delta?.content, !text.isEmpty {
                continuation.yield(.text(text))
            }
            if let calls = choice.delta?.tool_calls {
                for call in calls {
                    let index = call.index ?? toolBuffers.count
                    var buffer = toolBuffers[index] ?? ToolCallBuffer()
                    if let id = call.id { buffer.id = id }
                    if let name = call.function?.name { buffer.name = name }
                    if let arguments = call.function?.arguments { buffer.arguments += arguments }
                    toolBuffers[index] = buffer
                }
            }
            if let reason = choice.finish_reason {
                if reason == ChatChunk.FinishReason.toolCalls.rawValue {
                    emitToolCalls()
                }
                didYieldFinish = true
                continuation.yield(.finish(
                    reason: ChatChunk.FinishReason(rawValue: reason) ?? .stop,
                    usage: nil
                ))
            }
        }
        continuation.finish()
    }

    // MARK: - Wire format

    private struct ChatBody: Encodable {
        let model: String
        let messages: [BodyMessage]
        let stream: Bool
        let temperature: Double?
        let top_p: Double?
        let max_tokens: Int?
        let tools: [ToolSpec]?
    }

    private struct BodyMessage: Encodable {
        let role: String
        let content: MessageContent?
        let tool_call_id: String?
        let tool_calls: [BodyToolCall]?
    }

    private enum MessageContent: Encodable {
        case text(String)
        case parts([ContentBlock])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text):
                try container.encode(text)
            case .parts(let parts):
                try container.encode(parts)
            }
        }
    }

    private struct ContentBlock: Encodable {
        struct ImageURL: Encodable { let url: String }

        let type: String
        let text: String?
        let image_url: ImageURL?

        static func text(_ value: String) -> ContentBlock {
            ContentBlock(type: "text", text: value, image_url: nil)
        }

        static func image(data: Data, mimeType: String) -> ContentBlock {
            ContentBlock(
                type: "image_url",
                text: nil,
                image_url: ImageURL(url: "data:\(mimeType);base64,\(data.base64EncodedString())")
            )
        }
    }

    private struct BodyToolCall: Encodable {
        struct Function: Encodable {
            let name: String
            let arguments: String
        }
        let id: String
        let type = "function"
        let function: Function
    }

    private struct ToolSpec: Encodable {
        struct FunctionSpec: Encodable {
            let name: String
            let description: String
            let parameters: ToolParameterSchema
        }
        let type = "function"
        let function: FunctionSpec
    }

    static func wireBodyData(for request: ChatRequest) throws -> Data {
        try JSONEncoder().encode(toWireBody(request))
    }

    private static func toWireBody(_ request: ChatRequest) -> ChatBody {
        let modelName = request.modelId.hasPrefix("\(RuntimeLlamaCpp.id):")
            ? String(request.modelId.dropFirst(RuntimeLlamaCpp.id.count + 1))
            : request.modelId

        let messages = request.messages.map(toWireMessage)
        let tools = request.tools.isEmpty ? nil : request.tools.map { tool in
            ToolSpec(function: .init(
                name: tool.id,
                description: tool.description,
                parameters: tool.parameters
            ))
        }

        return ChatBody(
            model: modelName,
            messages: messages,
            stream: request.stream,
            temperature: request.sampling.temperature,
            top_p: request.sampling.topP,
            max_tokens: request.sampling.maxTokens,
            tools: tools
        )
    }

    private static func toWireMessage(_ message: Message) -> BodyMessage {
        let content: MessageContent?
        if message.parts.contains(where: { part in
            if case .image = part { return true }
            return false
        }) {
            let blocks = message.parts.compactMap { part -> ContentBlock? in
                switch part {
                case .text(let text):
                    return .text(text)
                case .image(let data, let mimeType):
                    return .image(data: data, mimeType: mimeType)
                case .audio, .video:
                    return nil
                }
            }
            content = .parts(blocks)
        } else if message.textContent.isEmpty, !message.toolCalls.isEmpty {
            content = nil
        } else {
            content = .text(message.textContent)
        }

        let calls = message.toolCalls.isEmpty ? nil : message.toolCalls.map { call in
            BodyToolCall(
                id: call.id,
                function: .init(
                    name: call.toolId,
                    arguments: String(data: call.argumentsJSON, encoding: .utf8) ?? "{}"
                )
            )
        }

        return BodyMessage(
            role: message.role.rawValue,
            content: content,
            tool_call_id: message.toolCallId,
            tool_calls: calls
        )
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
