import Foundation
import LLMCore
import ModelRegistry
import AgentKit
import SwiftUI

/// Observable state + consent plumbing for the Agents tab.
///
/// Stores a running transcript of the agent's turns, tool calls, tool
/// results, and errors. Implements `ConsentProvider` itself so every
/// tool-call gate routes through a published `pendingConsent` request
/// that the SwiftUI layer renders as a dialog.
@MainActor
final class AgentsTabViewModel: ObservableObject, ConsentProvider {

    // MARK: - Transcript

    struct Turn: Identifiable {
        enum Kind {
            case assistant(String)
            case toolCall(toolId: String, argumentsJSON: Data)
            case toolResult(toolId: String, output: String)
            case toolError(toolId: String, message: String)
            case note(String)
        }
        let id = UUID()
        var kind: Kind
    }

    @Published private(set) var turns: [Turn] = []
    @Published var input: String = ""
    @Published private(set) var isRunning: Bool = false
    @Published var enableWebSearch: Bool = false

    // MARK: - Consent

    struct PendingConsent: Identifiable {
        let id = UUID()
        let toolId: String
        let argumentsJSON: Data
    }
    @Published var pendingConsent: PendingConsent?
    private var consentContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]

    // MARK: - Wiring

    private weak var store: AppStore?
    private var sessionTask: Task<Void, Never>?

    func bind(to store: AppStore) { self.store = store }

    // MARK: - Run / cancel

    func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isRunning else { return }
        input = ""
        turns.append(Turn(kind: .note("user · \(prompt)")))

        sessionTask = Task { [weak self] in
            await self?.run(prompt: prompt)
        }
    }

    func cancel() {
        sessionTask?.cancel()
        sessionTask = nil
        isRunning = false
    }

    private func run(prompt: String) async {
        guard let store else { return }
        guard let resolved = await store.selected else {
            turns.append(Turn(kind: .note("⚠️ no model selected — open Settings")))
            return
        }
        let (runtime, info) = resolved
        guard info.capabilities.toolUse else {
            turns.append(Turn(kind: .note("⚠️ \(info.displayName) does not support tool use")))
            return
        }

        var tools: [AgentTool] = [
            ReadFileTool(),
            WriteFileTool(),
            ListDirTool(),
            RunShellTool()
        ]
        if enableWebSearch {
            tools.append(WebSearchTool())
        }

        let session = AgentSession(
            runtime: runtime,
            modelInfo: info,
            tools: tools,
            consent: self
        )

        isRunning = true
        defer { isRunning = false }

        var currentAssistant = ""
        for await event in session.run(userPrompt: prompt) {
            if Task.isCancelled { break }
            switch event {
            case .assistantDelta(let delta):
                currentAssistant += delta
                if let last = turns.last, case .assistant = last.kind,
                   last.id == turns.last?.id {
                    // Mutate in place on the most recent assistant turn.
                    turns[turns.count - 1].kind = .assistant(currentAssistant)
                } else {
                    turns.append(Turn(kind: .assistant(delta)))
                    currentAssistant = delta
                }
            case .assistantTurnComplete:
                currentAssistant = ""
            case .toolCall(_, let toolId, let args):
                turns.append(Turn(kind: .toolCall(toolId: toolId, argumentsJSON: args)))
            case .toolResult(_, let toolId, let output):
                turns.append(Turn(kind: .toolResult(toolId: toolId, output: output)))
            case .toolError(_, let toolId, let err):
                turns.append(Turn(kind: .toolError(toolId: toolId, message: err)))
            case .completed:
                turns.append(Turn(kind: .note("✓ session complete")))
            case .failed(let msg):
                turns.append(Turn(kind: .note("✗ \(msg)")))
            }
        }
    }

    func reset() {
        cancel()
        turns = []
        input = ""
    }

    // MARK: - ConsentProvider

    nonisolated func approve(toolId: String, argumentsJSON: Data) async -> Bool {
        await withCheckedContinuation { cont in
            Task { @MainActor in
                let pending = PendingConsent(toolId: toolId, argumentsJSON: argumentsJSON)
                self.consentContinuations[pending.id] = cont
                self.pendingConsent = pending
            }
        }
    }

    /// Called by the view layer when the user decides.
    func resolveConsent(_ id: UUID, allow: Bool) {
        pendingConsent = nil
        consentContinuations.removeValue(forKey: id)?.resume(returning: allow)
    }
}
