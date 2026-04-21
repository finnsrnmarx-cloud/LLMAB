import Foundation

/// JSON-serialisable parameter schema for a tool. We mirror the OpenAI-style
/// "function" schema because Ollama, llama-server, and mlx-lm all accept it;
/// translation to provider-specific shapes happens in the adapter.
public struct ToolParameterSchema: Sendable, Hashable, Codable {
    public var type: String            // "object", "string", ...
    public var properties: [String: PropertySchema]
    public var required: [String]

    public init(type: String = "object",
                properties: [String: PropertySchema] = [:],
                required: [String] = []) {
        self.type = type
        self.properties = properties
        self.required = required
    }

    public struct PropertySchema: Sendable, Hashable, Codable {
        public var type: String        // "string", "integer", "boolean", "array", "object"
        public var description: String?
        public var enumValues: [String]?

        public init(type: String, description: String? = nil, enumValues: [String]? = nil) {
            self.type = type
            self.description = description
            self.enumValues = enumValues
        }

        private enum CodingKeys: String, CodingKey {
            case type, description
            case enumValues = "enum"
        }
    }
}

/// A tool definition as offered by the app to the model.
public struct Tool: Sendable, Hashable, Codable, Identifiable {
    public var id: String              // logical name, e.g. "read_file"
    public var description: String
    public var parameters: ToolParameterSchema

    public init(id: String, description: String, parameters: ToolParameterSchema) {
        self.id = id
        self.description = description
        self.parameters = parameters
    }
}

/// A tool call produced by the model. `arguments` holds raw JSON bytes — the
/// caller decodes into the tool's own input struct.
public struct ToolCall: Sendable, Hashable, Codable, Identifiable {
    public var id: String              // provider-assigned call id
    public var toolId: String          // matches `Tool.id`
    public var argumentsJSON: Data

    public init(id: String, toolId: String, argumentsJSON: Data) {
        self.id = id
        self.toolId = toolId
        self.argumentsJSON = argumentsJSON
    }
}
