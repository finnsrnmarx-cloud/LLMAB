import Foundation

/// Wire-format structs for the Ollama HTTP API. Kept internal to this module;
/// the adapter maps them onto `LLMCore` types before anything leaks out.
enum OllamaDTO {

    // MARK: - GET /api/tags

    struct TagsResponse: Decodable, Sendable {
        let models: [TagModel]
    }

    struct TagModel: Decodable {
        let name: String                    // "gemma-4:e4b"
        let model: String?                  // sometimes present, mirrors name
        let size: Int64?
        let digest: String?
        let modified_at: String?
        let details: Details?

        struct Details: Decodable {
            let format: String?             // "gguf"
            let family: String?             // "gemma"
            let families: [String]?
            let parameter_size: String?     // "4.5B"
            let quantization_level: String? // "Q4_K_M"
        }
    }

    // MARK: - GET /api/ps (loaded models)

    struct PSResponse: Decodable {
        let models: [PSModel]?
    }

    struct PSModel: Decodable {
        let name: String
        let size_vram: Int64?
        let expires_at: String?
    }

    // MARK: - POST /api/chat

    struct ChatRequestBody: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let options: ChatOptions?
        let tools: [ToolSpec]?
    }

    struct ChatMessage: Encodable {
        let role: String            // "system" | "user" | "assistant" | "tool"
        let content: String
        let images: [String]?       // base64-encoded
        let tool_call_id: String?
    }

    struct ChatOptions: Encodable {
        let temperature: Double?
        let top_p: Double?
        let top_k: Int?
        let num_predict: Int?
        let stop: [String]?
    }

    struct ToolSpec: Encodable {
        let type: String            // "function"
        let function: FunctionSpec

        struct FunctionSpec: Encodable {
            let name: String
            let description: String
            let parameters: ParametersSpec
        }

        struct ParametersSpec: Encodable {
            let type: String
            let properties: [String: PropertySpec]
            let required: [String]
        }

        struct PropertySpec: Encodable {
            let type: String
            let description: String?
            let `enum`: [String]?
        }
    }

    struct ChatStreamChunk: Decodable {
        let model: String?
        let created_at: String?
        let message: ChatStreamMessage?
        let done: Bool?
        let done_reason: String?
        let total_duration: Int64?
        let eval_count: Int?
        let prompt_eval_count: Int?
    }

    struct ChatStreamMessage: Decodable {
        let role: String?
        let content: String?
        let tool_calls: [StreamToolCall]?

        struct StreamToolCall: Decodable {
            let id: String?
            let function: StreamFunction?

            struct StreamFunction: Decodable {
                let name: String?
                // Ollama emits `arguments` as a nested JSON object, not a
                // string. We preserve it as raw JSON bytes.
                let arguments: [String: AnyCodable]?
            }
        }
    }

    // MARK: - POST /api/pull

    struct PullRequestBody: Encodable {
        let model: String
        let stream: Bool
    }

    struct PullStreamChunk: Decodable {
        let status: String
        let digest: String?
        let total: Int64?
        let completed: Int64?
    }
}

// MARK: - AnyCodable (minimal, for tool-call arguments)

/// Erased JSON value just good enough to re-encode tool-call arguments back
/// out to bytes. We don't inspect the structure here; the consuming tool
/// handler does its own decoding.
struct AnyCodable: Codable, Hashable {
    let value: Value

    enum Value: Hashable {
        case null
        case bool(Bool)
        case int(Int64)
        case double(Double)
        case string(String)
        case array([AnyCodable])
        case object([String: AnyCodable])
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = .null; return }
        if let b = try? c.decode(Bool.self) { value = .bool(b); return }
        if let i = try? c.decode(Int64.self) { value = .int(i); return }
        if let d = try? c.decode(Double.self) { value = .double(d); return }
        if let s = try? c.decode(String.self) { value = .string(s); return }
        if let arr = try? c.decode([AnyCodable].self) { value = .array(arr); return }
        if let obj = try? c.decode([String: AnyCodable].self) { value = .object(obj); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
