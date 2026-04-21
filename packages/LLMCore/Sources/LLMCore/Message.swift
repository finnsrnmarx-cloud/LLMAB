import Foundation

/// A single part of a multimodal message. Runtime adapters translate these
/// into whatever content format the underlying API expects (Ollama's
/// `images`/`audio` arrays, llama.cpp's multimodal embeddings, MLX's tokenizer
/// input, etc.).
public enum ContentPart: Sendable, Hashable, Codable {
    case text(String)
    case image(Data, mimeType: String)
    case audio(Data, mimeType: String)
    case video(Data, mimeType: String)

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }
}

public enum MessageRole: String, Sendable, Hashable, Codable {
    case system
    case user
    case assistant
    case tool
}

public struct Message: Sendable, Hashable, Codable, Identifiable {

    public var id: UUID
    public var role: MessageRole
    public var parts: [ContentPart]

    /// If `role == .assistant`, the assistant may have emitted tool-calls
    /// alongside (or instead of) text.
    public var toolCalls: [ToolCall]

    /// If `role == .tool`, which pending call is being responded to.
    public var toolCallId: String?

    public init(id: UUID = UUID(),
                role: MessageRole,
                parts: [ContentPart] = [],
                toolCalls: [ToolCall] = [],
                toolCallId: String? = nil) {
        self.id = id
        self.role = role
        self.parts = parts
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    /// Convenience: concatenate every `.text` part.
    public var textContent: String {
        parts.compactMap { part in
            if case .text(let s) = part { return s } else { return nil }
        }.joined()
    }

    public static func user(_ text: String) -> Message {
        Message(role: .user, parts: [.text(text)])
    }

    public static func system(_ text: String) -> Message {
        Message(role: .system, parts: [.text(text)])
    }

    public static func assistant(_ text: String) -> Message {
        Message(role: .assistant, parts: [.text(text)])
    }
}
