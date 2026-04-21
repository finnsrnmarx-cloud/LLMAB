import Foundation
import LLMCore

/// Run a shell command. Requires consent on every call.
///
/// Only commands whose program (first whitespace token) appears in
/// `allowedPrograms` are ever attempted — this is a defense-in-depth
/// additional to the consent gate. Defaults to a small, common set.
public struct RunShellTool: AgentTool {
    public let id = "run_shell"
    public let description = "Run a shell command (bash -c). Returns combined stdout + stderr. Every call is routed through the consent dialog."
    public let requiresConsent = true
    public let parameters = ToolParameterSchema(
        type: "object",
        properties: [
            "command": .init(type: "string",
                             description: "Shell command, executed via `bash -c`.")
        ],
        required: ["command"]
    )

    public let allowedPrograms: Set<String>

    public init(allowedPrograms: Set<String> = Self.defaultAllowedPrograms) {
        self.allowedPrograms = allowedPrograms
    }

    public static let defaultAllowedPrograms: Set<String> = [
        "ls", "cat", "grep", "rg", "wc", "head", "tail", "find",
        "pwd", "echo", "awk", "sed", "diff", "stat", "file",
        "git", "swift", "xcodebuild", "swiftlint",
        "npm", "node", "python", "python3", "pip", "pip3",
        "make", "cargo", "gcc", "clang"
    ]

    private struct Args: Decodable { let command: String }

    public func execute(arguments: Data) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: arguments)
        let command = args.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return "<empty command>" }

        let program = command
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? ""
        guard allowedPrograms.contains(program) else {
            throw AgentKitError.toolFailed(
                name: id,
                reason: "program '\(program)' is not on the allowlist"
            )
        }

        return try await Self.shell(command)
    }

    private static func shell(_ command: String) async throws -> String {
        #if canImport(Foundation) && !os(iOS) && !os(tvOS) && !os(watchOS)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8) ?? ""
                cont.resume(returning: out)
            }
            do { try process.run() }
            catch { cont.resume(throwing: error) }
        }
        #else
        throw AgentKitError.toolFailed(name: "run_shell", reason: "Process unavailable on this platform")
        #endif
    }
}
