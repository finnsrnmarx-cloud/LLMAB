import XCTest
import LLMCore
@testable import AgentKit

/// Exercises the tool-use loop: start → assistantDelta → toolCall → consent
/// gate → tool execution → tool result → model final answer → completed /
/// failed.
///
/// All LLM and tool interactions use in-file stubs so tests run with zero
/// network / subprocess.
final class AgentSessionTests: XCTestCase {

    // MARK: - Scenario 1: no tool calls → finishes on first assistant turn.

    func testPlainAnswerFinishesWithoutToolCalls() async {
        let runtime = StubRuntime(script: [[
            .text("Hello"),
            .text(" there"),
            .finish(reason: .stop, usage: nil)
        ]])
        let info = toolCapableInfo()
        let session = AgentSession(
            runtime: runtime,
            modelInfo: info,
            tools: [],
            consent: AlwaysApprove()
        )

        var assistantText = ""
        var saw: [String] = []
        for await event in session.run(userPrompt: "hi") {
            switch event {
            case .assistantDelta(let d): assistantText += d
            case .assistantTurnComplete: saw.append("turn")
            case .completed:             saw.append("completed")
            case .failed(let m):         XCTFail("unexpected failure: \(m)")
            default:                      break
            }
        }
        XCTAssertEqual(assistantText, "Hello there")
        XCTAssertEqual(saw, ["turn", "completed"])
    }

    // MARK: - Scenario 2: one tool call, approved, tool returns → final answer.

    func testToolCallExecutesWhenConsentApproved() async {
        let call = ToolCall(
            id: "call-1",
            toolId: "echo",
            argumentsJSON: #"{"text":"hi"}"#.data(using: .utf8)!
        )
        let runtime = StubRuntime(script: [
            [.toolCall(call), .finish(reason: .toolCalls, usage: nil)],
            [.text("got it: hi"), .finish(reason: .stop, usage: nil)]
        ])
        let info = toolCapableInfo()

        var toolRan = false
        let tool = ClosureTool(
            id: "echo",
            requiresConsent: false
        ) { _ in
            toolRan = true
            return "echoed"
        }

        let session = AgentSession(
            runtime: runtime,
            modelInfo: info,
            tools: [tool],
            consent: AlwaysApprove()
        )

        var events: [String] = []
        for await event in session.run(userPrompt: "use echo") {
            switch event {
            case .toolCall(_, let id, _):       events.append("call:\(id)")
            case .toolResult(_, let id, _):     events.append("result:\(id)")
            case .toolError(_, let id, let e):  XCTFail("tool error \(id): \(e)")
            case .completed:                    events.append("completed")
            case .failed(let m):                XCTFail("unexpected failure: \(m)")
            default:                             break
            }
        }
        XCTAssertTrue(toolRan, "tool body never executed")
        XCTAssertEqual(events, ["call:echo", "result:echo", "completed"])
    }

    // MARK: - Scenario 3: tool requires consent and consent is denied.

    func testConsentDeniedRouteProducesToolErrorNotExecution() async {
        let call = ToolCall(
            id: "call-1",
            toolId: "shell",
            argumentsJSON: #"{"command":"ls"}"#.data(using: .utf8)!
        )
        // Model issues the tool call, then on the follow-up (after the
        // tool-error result) produces a final text turn and stops.
        let runtime = StubRuntime(script: [
            [.toolCall(call), .finish(reason: .toolCalls, usage: nil)],
            [.text("user said no"), .finish(reason: .stop, usage: nil)]
        ])

        var toolRan = false
        let tool = ClosureTool(
            id: "shell",
            requiresConsent: true
        ) { _ in
            toolRan = true
            return "shouldn't run"
        }

        let session = AgentSession(
            runtime: runtime,
            modelInfo: toolCapableInfo(),
            tools: [tool],
            consent: AlwaysDeny()
        )

        var errors: [String] = []
        for await event in session.run(userPrompt: "rm -rf /") {
            if case .toolError(_, _, let msg) = event {
                errors.append(msg)
            }
        }
        XCTAssertFalse(toolRan, "consent was denied but tool executed")
        XCTAssertEqual(errors, ["consent denied"])
    }

    // MARK: - Scenario 4: model that lacks toolUse capability fails fast.

    func testModelWithoutToolUseCapabilityFailsFast() async {
        var caps = ModelCapabilities.textOnly
        caps.textOut = true
        caps.toolUse = false
        let info = ModelInfo(
            id: "stub:plain",
            rawName: "plain",
            displayName: "Plain Model",
            runtimeId: "stub",
            family: "stub",
            capabilities: caps
        )

        let session = AgentSession(
            runtime: StubRuntime(script: []),   // never consulted
            modelInfo: info,
            tools: [],
            consent: AlwaysApprove()
        )

        var failed: String?
        for await event in session.run(userPrompt: "hi") {
            if case .failed(let m) = event { failed = m }
        }
        XCTAssertNotNil(failed)
        XCTAssertTrue(failed!.contains("tool use"), "expected tool-use error, got \(failed!)")
    }

    // MARK: - Scenario 5: unknown tool id → tool error, loop continues.

    func testUnknownToolIdProducesToolErrorButContinuesLoop() async {
        let unknown = ToolCall(
            id: "call-1",
            toolId: "does_not_exist",
            argumentsJSON: Data("{}".utf8)
        )
        let runtime = StubRuntime(script: [
            [.toolCall(unknown), .finish(reason: .toolCalls, usage: nil)],
            [.text("ok moving on"), .finish(reason: .stop, usage: nil)]
        ])

        let session = AgentSession(
            runtime: runtime,
            modelInfo: toolCapableInfo(),
            tools: [],   // empty — unknown tool
            consent: AlwaysApprove()
        )

        var errs: [String] = []
        var didComplete = false
        for await event in session.run(userPrompt: "go") {
            switch event {
            case .toolError(_, _, let e): errs.append(e)
            case .completed:              didComplete = true
            default:                       break
            }
        }
        XCTAssertEqual(errs, ["no such tool"])
        XCTAssertTrue(didComplete)
    }

    // MARK: - Scenario 6: maxSteps budget exhaustion.

    func testBudgetExhaustionAfterNRepeatedToolCalls() async {
        let call = ToolCall(id: "call", toolId: "loop", argumentsJSON: Data("{}".utf8))
        // The model keeps asking to call the same tool, 10 times over.
        let turns = Array(repeating: [
            ChatChunk.toolCall(call),
            ChatChunk.finish(reason: .toolCalls, usage: nil)
        ], count: 10)
        let runtime = StubRuntime(script: turns)

        let tool = ClosureTool(
            id: "loop",
            requiresConsent: false
        ) { _ in "looped" }

        let session = AgentSession(
            runtime: runtime,
            modelInfo: toolCapableInfo(),
            tools: [tool],
            consent: AlwaysApprove(),
            maxSteps: 3   // way under the model's pretend-forever
        )

        var failure: String?
        for await event in session.run(userPrompt: "loop") {
            if case .failed(let m) = event { failure = m }
        }
        XCTAssertNotNil(failure)
        XCTAssertTrue(failure!.contains("budget"),
                      "expected budget exceeded error, got \(failure!)")
    }
}

// MARK: - Stubs

/// A prerecorded LLMRuntime. Each inner array is one turn's worth of chunks.
/// Calls to `chat(...)` dequeue the next script entry.
final class StubRuntime: LLMRuntime, @unchecked Sendable {
    let id = "stub"
    let displayName = "Stub Runtime"
    private var script: [[ChatChunk]]
    private let queue = DispatchQueue(label: "stub.runtime.queue")

    init(script: [[ChatChunk]]) { self.script = script }

    func isAvailable() async -> Bool { true }
    func discoverModels() async throws -> [ModelInfo] { [] }

    func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        let chunks: [ChatChunk] = queue.sync {
            guard !script.isEmpty else { return [] }
            return script.removeFirst()
        }
        return AsyncThrowingStream { cont in
            for chunk in chunks { cont.yield(chunk) }
            cont.finish()
        }
    }
}

/// A minimal AgentTool backed by a closure — avoids spinning up shell /
/// filesystem for the test scenarios.
struct ClosureTool: AgentTool {
    let id: String
    let description: String = "test tool"
    let parameters: ToolParameterSchema = ToolParameterSchema()
    let requiresConsent: Bool
    let body: @Sendable (Data) async throws -> String

    func execute(arguments: Data) async throws -> String {
        try await body(arguments)
    }
}

// MARK: - Helpers

private func toolCapableInfo() -> ModelInfo {
    var caps = ModelCapabilities.textOnly
    caps.textOut = true
    caps.toolUse = true
    return ModelInfo(
        id: "stub:tool-capable",
        rawName: "tool-capable",
        displayName: "Tool-capable Model",
        runtimeId: "stub",
        family: "stub",
        capabilities: caps
    )
}
