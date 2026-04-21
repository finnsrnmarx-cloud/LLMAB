import Foundation
import LLMCore

public struct ListDirTool: AgentTool {
    public let id = "list_dir"
    public let description = "List entries in a directory, one per line."
    public let requiresConsent = false
    public let parameters = ToolParameterSchema(
        type: "object",
        properties: [
            "path": .init(type: "string", description: "Absolute directory path."),
            "include_hidden": .init(type: "boolean",
                                    description: "Include dotfiles. Default false.")
        ],
        required: ["path"]
    )

    private struct Args: Decodable {
        let path: String
        let include_hidden: Bool?
    }

    public init() {}

    public func execute(arguments: Data) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: arguments)
        let url = URL(fileURLWithPath: args.path)
        let options: FileManager.DirectoryEnumerationOptions =
            (args.include_hidden ?? false) ? [] : [.skipsHiddenFiles]
        let entries = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: options
        )
        let lines: [String] = entries.map { entry in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir)
            let marker = isDir.boolValue ? "/" : ""
            return "\(entry.lastPathComponent)\(marker)"
        }
        .sorted()
        return lines.isEmpty ? "<empty directory>" : lines.joined(separator: "\n")
    }
}
