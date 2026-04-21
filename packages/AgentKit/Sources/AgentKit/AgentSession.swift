import Foundation
import LLMCore

/// Events the UI observes while the session runs.
public enum AgentEvent: Sendable {
    case assistantDelta(String)
    case assistantTurnComplete(String)
    case toolCall(id: String, toolId: String, argumentsJSON: Data)
    case toolResult(id: String, toolId: String, output: String)
    case toolError(id: String, toolId: String, error: String)
    case completed
    case failed(String)
}

/// A running multi-step tool-use loop. One AgentSession = one user ask.
public final class AgentSession: @unchecked Sendable {

    private let runtime: any LLMRuntime
    private let modelInfo: ModelInfo
    private let tools: [AgentTool]
    private let consent: ConsentProvider
    private let maxSteps: Int

    public init(runtime: any LLMRuntime,
                modelInfo: ModelInfo,
                tools: [AgentTool],
                consent: ConsentProvider = AlwaysDeny(),
                maxSteps: Int = 12) {
        self.runtime = runtime
        self.modelInfo = modelInfo
        self.tools = tools
        self.consent = consent
        self.maxSteps = maxSteps
    }

    /// Drive the loop. Yields `AgentEvent`s as the conversation evolves;
    /// terminates on `.completed` or `.failed`.
    public func run(userPrompt: String,
                    systemPrompt: String? = nil) -> AsyncStream<AgentEvent> {
        AsyncStream<AgentEvent> { continuation in
            let task = Task {
                await self.loop(userPrompt: userPrompt,
                                systemPrompt: systemPrompt,
                                continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func loop(userPrompt: String,
                      systemPrompt: String?,
                      continuation: AsyncStream<AgentEvent>.Continuation) async {
        guard modelInfo.capabilities.toolUse else {
            continuation.yield(.failed(AgentKitError.modelNoToolUse.description))
            continuation.finish()
            return
        }

        var history: [Message] = []
        if let s = systemPrompt {
            history.append(.system(s))
        } else {
            history.append(.system(Self.defaultSystemPrompt))
        }
        history.append(.user(userPrompt))

        let coreTools = tools.map(\.asLLMCoreTool)
        var step = 0

        outer: while step < maxSteps {
            step += 1

            var assistantText = ""
            var pendingCalls: [ToolCall] = []

            let req = ChatRequest(
                modelId: modelInfo.id,
                messages: history,
                tools: coreTools,
                sampling: .balanced,
                stream: true
            )

            do {
                for try await chunk in runtime.chat(req) {
                    if Task.isCancelled { break outer }
                    switch chunk {
                    case .text(let delta):
                        assistantText += delta
                        continuation.yield(.assistantDelta(delta))
                    case .toolCall(let call):
                        pendingCalls.append(call)
                        continuation.yield(.toolCall(
                            id: call.id,
                            toolId: call.toolId,
                            argumentsJSON: call.argumentsJSON
                        ))
                    case .finish:
                        break
                    }
                }
            } catch {
                continuation.yield(.failed(String(describing: error)))
                continuation.finish()
                return
            }

            // Record the assistant turn in history.
            history.append(Message(
                role: .assistant,
                parts: assistantText.isEmpty ? [] : [.text(assistantText)],
                toolCalls: pendingCalls
            ))
            if !assistantText.isEmpty {
                continuation.yield(.assistantTurnComplete(assistantText))
            }

            if pendingCalls.isEmpty { break }  // model is done asking for tools

            // Execute each tool call, append results to history.
            for call in pendingCalls {
                guard let tool = tools.first(where: { $0.id == call.toolId }) else {
                    continuation.yield(.toolError(
                        id: call.id, toolId: call.toolId,
                        error: "no such tool"
                    ))
                    history.append(Message(
                        role: .tool,
                        parts: [.text("error: no such tool")],
                        toolCallId: call.id
                    ))
                    continue
                }
                if tool.requiresConsent {
                    let ok = await consent.approve(
                        toolId: tool.id,
                        argumentsJSON: call.argumentsJSON
                    )
                    if !ok {
                        continuation.yield(.toolError(
                            id: call.id, toolId: tool.id,
                            error: "consent denied"
                        ))
                        history.append(Message(
                            role: .tool,
                            parts: [.text("error: user denied consent")],
                            toolCallId: call.id
                        ))
                        continue
                    }
                }
                do {
                    let output = try await tool.execute(arguments: call.argumentsJSON)
                    continuation.yield(.toolResult(
                        id: call.id, toolId: tool.id, output: output
                    ))
                    history.append(Message(
                        role: .tool,
                        parts: [.text(output)],
                        toolCallId: call.id
                    ))
                } catch {
                    let reason = String(describing: error)
                    continuation.yield(.toolError(
                        id: call.id, toolId: tool.id, error: reason
                    ))
                    history.append(Message(
                        role: .tool,
                        parts: [.text("error: \(reason)")],
                        toolCallId: call.id
                    ))
                }
            }
        }

        if step >= maxSteps {
            continuation.yield(.failed(AgentKitError.budgetExceeded(maxSteps: maxSteps).description))
        } else {
            continuation.yield(.completed)
        }
        continuation.finish()
    }

    private static let defaultSystemPrompt = """
    You are ω, an on-device coding and file-manipulation agent. You have
    tools for reading and writing files, listing directories, running
    shell commands (every shell command is consent-gated), and optional
    web search. Prefer concise, decisive actions. Summarise results as
    you go; when you've completed the task, stop calling tools and write
    a final summary.
    """
}
