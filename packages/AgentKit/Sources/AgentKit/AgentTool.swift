import Foundation
import LLMCore

/// A single callable tool exposed to the model.
public protocol AgentTool: Sendable {
    /// Stable identifier. Matches `LLMCore.Tool.id`.
    var id: String { get }

    /// Short, user-facing rationale. Shown in the consent dialog when needed.
    var description: String { get }

    /// JSON schema for the tool's arguments.
    var parameters: ToolParameterSchema { get }

    /// Whether each invocation must route through the `ConsentProvider`
    /// before running. `run_shell` sets this; `read_file`, `list_dir`,
    /// `web_search` typically don't.
    var requiresConsent: Bool { get }

    /// Execute the tool. `arguments` is the raw JSON the model emitted.
    /// Return the string to send back as the tool's response. Throw to
    /// surface a failure.
    func execute(arguments: Data) async throws -> String
}

public extension AgentTool {
    /// Convenience: expose the tool as an `LLMCore.Tool` the adapter can send
    /// in a `ChatRequest`.
    var asLLMCoreTool: Tool {
        Tool(id: id, description: description, parameters: parameters)
    }
}

/// Consent gate. Host apps implement this (e.g. a SwiftUI alert) and the
/// session awaits its decision for each tool invocation that needs it.
public protocol ConsentProvider: Sendable {
    /// Return true to allow the tool call, false to reject.
    func approve(toolId: String, argumentsJSON: Data) async -> Bool
}

/// Built-in ConsentProvider that always approves (tests / CLI with
/// `--yes-to-all`).
public struct AlwaysApprove: ConsentProvider {
    public init() {}
    public func approve(toolId: String, argumentsJSON: Data) async -> Bool { true }
}

/// Built-in ConsentProvider that always denies (for dry-run previews).
public struct AlwaysDeny: ConsentProvider {
    public init() {}
    public func approve(toolId: String, argumentsJSON: Data) async -> Bool { false }
}
