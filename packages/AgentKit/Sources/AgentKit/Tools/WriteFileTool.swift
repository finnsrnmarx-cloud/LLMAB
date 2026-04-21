import Foundation
import LLMCore

public struct WriteFileTool: AgentTool {
    public let id = "write_file"
    public let description = "Write a string to a file, creating parent directories as needed."
    public let requiresConsent = true
    public let parameters = ToolParameterSchema(
        type: "object",
        properties: [
            "path": .init(type: "string", description: "Absolute file path."),
            "contents": .init(type: "string", description: "Text contents to write.")
        ],
        required: ["path", "contents"]
    )

    private struct Args: Decodable {
        let path: String
        let contents: String
    }

    public init() {}

    public func execute(arguments: Data) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: arguments)
        let url = URL(fileURLWithPath: args.path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try args.contents.write(to: url, atomically: true, encoding: .utf8)
        return "wrote \(args.contents.utf8.count) bytes to \(args.path)"
    }
}
