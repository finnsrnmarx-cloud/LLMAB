import Foundation

/// Sampling knobs. Adapters map these onto the underlying runtime's parameter
/// names. Anything nil is left at the runtime's default.
public struct SamplingConfig: Sendable, Hashable, Codable {
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var maxTokens: Int?

    /// Gemma 4's configurable "thinking" budget, in tokens. Nil = off.
    public var thinkingTokenBudget: Int?

    /// Stop sequences.
    public var stop: [String]

    public init(temperature: Double? = nil,
                topP: Double? = nil,
                topK: Int? = nil,
                maxTokens: Int? = nil,
                thinkingTokenBudget: Int? = nil,
                stop: [String] = []) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.thinkingTokenBudget = thinkingTokenBudget
        self.stop = stop
    }

    public static let balanced = SamplingConfig(temperature: 0.7, topP: 0.95, maxTokens: 2048)
    public static let deterministic = SamplingConfig(temperature: 0, topP: 1.0, maxTokens: 2048)
}

public struct ChatRequest: Sendable, Hashable, Codable {

    public var modelId: String
    public var messages: [Message]
    public var tools: [Tool]
    public var sampling: SamplingConfig

    /// When true, the adapter returns an `AsyncThrowingStream<ChatChunk, …>`
    /// that yields token deltas. When false, the adapter still returns a
    /// stream, but with a single terminal chunk carrying the full response.
    public var stream: Bool

    public init(modelId: String,
                messages: [Message],
                tools: [Tool] = [],
                sampling: SamplingConfig = .balanced,
                stream: Bool = true) {
        self.modelId = modelId
        self.messages = messages
        self.tools = tools
        self.sampling = sampling
        self.stream = stream
    }
}

/// One event in a streaming chat response.
public enum ChatChunk: Sendable, Hashable {
    /// An incremental text token delta.
    case text(String)

    /// The model emitted a full tool call.
    case toolCall(ToolCall)

    /// Generation finished for this turn.
    case finish(reason: FinishReason, usage: Usage?)

    public enum FinishReason: String, Sendable, Hashable, Codable {
        case stop
        case length
        case toolCalls = "tool_calls"
        case error
        case cancelled
    }

    public struct Usage: Sendable, Hashable, Codable {
        public var promptTokens: Int?
        public var completionTokens: Int?
        public var totalTokens: Int?
        public var latencyMs: Int?

        public init(promptTokens: Int? = nil,
                    completionTokens: Int? = nil,
                    totalTokens: Int? = nil,
                    latencyMs: Int? = nil) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
            self.latencyMs = latencyMs
        }
    }
}
