import Foundation
import LLMCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RuntimeDeepSeek {
    public static let id = "deepseek"
    public static let defaultEndpoint = URL(string: "https://api.deepseek.com")!
}

/// OpenAI-compatible cloud adapter for DeepSeek. It is intentionally text /
/// tool / reasoning only: no image or video parts are accepted until DeepSeek
/// exposes an official multimodal API surface we can capability-gate.
public final class DeepSeekRuntime: LLMRuntime, @unchecked Sendable {
    public let id = RuntimeDeepSeek.id
    public let displayName = "DeepSeek · cloud API"

    private let endpoint: URL
    private let session: URLSession
    private let apiKeyProvider: @Sendable () -> String?

    public init(endpoint: URL = RuntimeDeepSeek.defaultEndpoint,
                session: URLSession = .shared,
                apiKeyProvider: @escaping @Sendable () -> String? = {
                    CloudAPIKeyStore.deepSeek.readAPIKey()
                }) {
        self.endpoint = endpoint
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    public func isAvailable() async -> Bool {
        apiKeyProvider()?.isEmpty == false
    }

    public func discoverModels() async throws -> [ModelInfo] {
        guard await isAvailable() else {
            throw LLMRuntimeError.unavailable("DeepSeek API key not configured")
        }
        return Self.knownModels
    }

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
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw LLMRuntimeError.unavailable("DeepSeek API key not configured")
        }

        var req = URLRequest(url: endpoint.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.authorizationHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        req.httpBody = try Self.wireBodyData(for: request)

        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            var collected = Data()
            for try await b in bytes { collected.append(b) }
            let body = String(data: collected, encoding: .utf8) ?? "<binary>"
            throw LLMRuntimeError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: body)
        }

        try await Self.parseStreamingResponse(bytes: bytes, continuation: continuation)
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
        let reasoning_effort: String?
    }

    private struct BodyMessage: Encodable {
        let role: String
        let content: String
        let tool_call_id: String?
        let tool_calls: [BodyToolCall]?
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

    public static func wireBodyData(for request: ChatRequest) throws -> Data {
        try JSONEncoder().encode(toWireBody(request))
    }

    public static func authorizationHeader(apiKey: String) -> String {
        "Bearer \(apiKey)"
    }

    public static func redactedAuthorizationHeader() -> String {
        "Bearer ********"
    }

    private static func toWireBody(_ request: ChatRequest) throws -> ChatBody {
        let modelName = request.modelId.hasPrefix("\(RuntimeDeepSeek.id):")
            ? String(request.modelId.dropFirst(RuntimeDeepSeek.id.count + 1))
            : request.modelId

        let messages = try request.messages.map(toWireMessage)
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
            stream: true,
            temperature: request.sampling.temperature,
            top_p: request.sampling.topP,
            max_tokens: request.sampling.maxTokens,
            tools: tools,
            reasoning_effort: request.sampling.thinkingTokenBudget == nil ? nil : "high"
        )
    }

    private static func toWireMessage(_ message: Message) throws -> BodyMessage {
        for part in message.parts {
            switch part {
            case .text:
                continue
            case .image, .audio, .video:
                throw LLMRuntimeError.unsupported("DeepSeek provider currently accepts text/tool messages only")
            }
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
            content: message.textContent,
            tool_call_id: message.toolCallId,
            tool_calls: calls
        )
    }

    // MARK: - Streaming parser

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let reasoning_content: String?
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

    private struct ToolCallBuffer {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private static func parseStreamingResponse(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation
    ) async throws {
        var toolBuffers: [Int: ToolCallBuffer] = [:]
        var didEmitToolCalls = false
        let decoder = JSONDecoder()

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

        for try await line in bytes.lines {
            if Task.isCancelled {
                continuation.finish(throwing: LLMRuntimeError.cancelled)
                return
            }
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
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
                continuation.yield(.finish(reason: finishReason(from: reason), usage: nil))
            }
        }
        continuation.finish()
    }

    private static func finishReason(from value: String) -> ChatChunk.FinishReason {
        ChatChunk.FinishReason(rawValue: value) ?? .error
    }

    // MARK: - Models

    private static let knownModels: [ModelInfo] = [
        ModelInfo(
            id: "\(RuntimeDeepSeek.id):deepseek-v4-flash",
            rawName: "deepseek-v4-flash",
            displayName: "DeepSeek V4 Flash",
            runtimeId: RuntimeDeepSeek.id,
            family: "deepseek-v4-flash",
            capabilities: deepSeekCapabilities(tags: ["deepseek", "cloud", "flash", "thinking"])
        ),
        ModelInfo(
            id: "\(RuntimeDeepSeek.id):deepseek-v4-pro",
            rawName: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro",
            runtimeId: RuntimeDeepSeek.id,
            family: "deepseek-v4-pro",
            capabilities: deepSeekCapabilities(tags: ["deepseek", "cloud", "pro", "thinking"])
        )
    ]

    private static func deepSeekCapabilities(tags: [String]) -> ModelCapabilities {
        ModelCapabilities(
            textIn: true,
            textOut: true,
            imageIn: false,
            imageOut: false,
            audioIn: false,
            audioOut: false,
            videoIn: false,
            videoOut: false,
            toolUse: true,
            thinking: true,
            contextTokens: 1_000_000,
            tags: tags,
            videoProfile: VideoIngestionProfile.none,
            privacy: .cloudProvider
        )
    }
}
