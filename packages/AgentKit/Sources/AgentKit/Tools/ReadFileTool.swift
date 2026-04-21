import Foundation
import LLMCore

public struct ReadFileTool: AgentTool {
    public let id = "read_file"
    public let description = "Read a text file from disk. Returns up to max_bytes bytes."
    public let requiresConsent = false
    public let parameters = ToolParameterSchema(
        type: "object",
        properties: [
            "path": .init(type: "string", description: "Absolute file path."),
            "max_bytes": .init(type: "integer",
                               description: "Optional cap on bytes to return. Default 64 KiB.")
        ],
        required: ["path"]
    )

    private struct Args: Decodable {
        let path: String
        let max_bytes: Int?
    }

    public init() {}

    public func execute(arguments: Data) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: arguments)
        let cap = args.max_bytes ?? (64 * 1024)
        let url = URL(fileURLWithPath: args.path)
        let data = try Data(contentsOf: url)
        let slice = data.prefix(cap)
        let truncated = data.count > cap
        let body = String(data: slice, encoding: .utf8)
            ?? "<binary file — \(data.count) bytes>"
        return truncated
            ? "\(body)\n\n⟨truncated — first \(cap) of \(data.count) bytes⟩"
            : body
    }
}
