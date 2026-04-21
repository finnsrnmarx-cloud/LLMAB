import Foundation
import LLMCore

/// Namespace for the tool-use agent loop.
///
/// A typical flow:
///   1. UI constructs an `AgentSession` with a set of `AgentTool`s and a
///      `ConsentProvider`.
///   2. UI calls `session.run(userPrompt:)` which drives the model with the
///      tool schema attached, executes any `ToolCall`s it emits, feeds
///      results back as `role == .tool` messages, and repeats until the
///      model stops asking for tools.
///   3. The UI observes `AgentSession.events` for turn/tool/complete
///      progress and renders the transcript.
///
/// All tool execution stays on-device. No third-party cloud services are
/// contacted; web_search, when enabled, uses DuckDuckGo's HTML endpoint
/// directly.
public enum AgentKit {
    public static let id = "agent-kit"
}

public enum AgentKitError: Error, Sendable, CustomStringConvertible {
    case toolNotFound(String)
    case toolFailed(name: String, reason: String)
    case consentDenied(String)
    case modelNoToolUse
    case budgetExceeded(maxSteps: Int)

    public var description: String {
        switch self {
        case .toolNotFound(let n): return "tool not found: \(n)"
        case .toolFailed(let n, let r): return "tool \(n) failed: \(r)"
        case .consentDenied(let n): return "user denied consent for \(n)"
        case .modelNoToolUse: return "this model does not support tool use"
        case .budgetExceeded(let m): return "exceeded tool-call budget of \(m) steps"
        }
    }
}
