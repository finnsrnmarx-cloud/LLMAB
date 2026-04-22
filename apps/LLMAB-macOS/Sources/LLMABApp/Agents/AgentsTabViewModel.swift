import Foundation
import LLMCore
import ModelRegistry
import AgentKit
import SwiftUI

/// A plain Sendable adapter that routes consent requests back to the
/// @MainActor view model via a stored closure. Keeps the view model free
/// of direct Sendable protocol conformance (which is thorny for @MainActor
/// classes in Swift 5.9).
struct ClosureConsent: ConsentProvider {
    let handler: @Sendable (String, Data) async -> Bool
    func approve(toolId: String, argumentsJSON: Data) async -> Bool {
        await handler(toolId, argumentsJSON)
    }
}

/// Observable state for the Agents tab. Stores a running transcript of the
/// agent's turns, tool calls, tool results, and errors. Consent gating is
/// routed through a stored `ClosureConsent` so the view model itself doesn't
/// need to conform to the Sendable `ConsentProvider` protocol.
@MainActor
final class AgentsTabViewModel: ObservableObject {

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

    @Published private(set) var turns: [Turn] = [] {
        didSet { schedulePersist() }
    }
    @Published var input: String = "" {
        didSet { schedulePersist() }
    }
    @Published private(set) var isRunning: Bool = false
    @Published var enableWebSearch: Bool = false {
        didSet { schedulePersist() }
    }

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
    private let persistence: PersistenceStore
    private var rehydrating: Bool = false

    init(persistence: PersistenceStore = .shared) {
        self.persistence = persistence
        rehydrate()
    }

    func bind(to store: AppStore) { self.store = store }

    private func rehydrate() {
        guard let saved = persistence.load(AgentsPersistedState.self,
                                           forKey: PersistenceKeys.agents) else {
            return
        }
        rehydrating = true
        defer { rehydrating = false }
        turns = saved.turns.map { entry in
            let kind: Turn.Kind
            switch entry.kind {
            case "assistant":
                kind = .assistant(entry.text ?? "")
            case "toolCall":
                kind = .toolCall(toolId: entry.toolId ?? "",
                                 argumentsJSON: entry.argumentsJSON ?? Data())
            case "toolResult":
                kind = .toolResult(toolId: entry.toolId ?? "",
                                   output: entry.text ?? "")
            case "toolError":
                kind = .toolError(toolId: entry.toolId ?? "",
                                  message: entry.text ?? "")
            default:
                kind = .note(entry.text ?? "")
            }
            return Turn(kind: kind)
        }
        input = saved.input
        enableWebSearch = saved.enableWebSearch
    }

    private func schedulePersist() {
        guard !rehydrating else { return }
        let entries: [AgentsPersistedState.Entry] = turns.map { turn in
            switch turn.kind {
            case .assistant(let s):
                return .init(kind: "assistant", text: s)
            case .toolCall(let id, let args):
                return .init(kind: "toolCall", toolId: id, argumentsJSON: args)
            case .toolResult(let id, let out):
                return .init(kind: "toolResult", text: out, toolId: id)
            case .toolError(let id, let msg):
                return .init(kind: "toolError", text: msg, toolId: id)
            case .note(let s):
                return .init(kind: "note", text: s)
            }
        }
        persistence.save(
            AgentsPersistedState(turns: entries,
                                 input: input,
                                 enableWebSearch: enableWebSearch),
            forKey: PersistenceKeys.agents
        )
    }

    func flushPersistence() {
        // schedulePersist already debounces; for the shutdown path we want
        // the synchronous variant.
        let entries: [AgentsPersistedState.Entry] = turns.map { turn in
            switch turn.kind {
            case .assistant(let s):             return .init(kind: "assistant", text: s)
            case .toolCall(let id, let args):   return .init(kind: "toolCall", toolId: id, argumentsJSON: args)
            case .toolResult(let id, let out):  return .init(kind: "toolResult", text: out, toolId: id)
            case .toolError(let id, let msg):   return .init(kind: "toolError", text: msg, toolId: id)
            case .note(let s):                  return .init(kind: "note", text: s)
            }
        }
        persistence.saveNow(
            AgentsPersistedState(turns: entries,
                                 input: input,
                                 enableWebSearch: enableWebSearch),
            forKey: PersistenceKeys.agents
        )
    }

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

        // Build a plain Sendable consent adapter that hops back to
        // MainActor to drive the @Published `pendingConsent`.
        let consent = ClosureConsent { [weak self] toolId, args in
            await self?.requestConsent(toolId: toolId, argumentsJSON: args) ?? false
        }
        let session = AgentSession(
            runtime: runtime,
            modelInfo: info,
            tools: tools,
            consent: consent
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

    // MARK: - Consent

    /// Called by ClosureConsent from an unisolated context. Runs on MainActor
    /// because the whole class is, so the @Published write is safe.
    func requestConsent(toolId: String, argumentsJSON: Data) async -> Bool {
        await withCheckedContinuation { cont in
            let pending = PendingConsent(toolId: toolId, argumentsJSON: argumentsJSON)
            self.consentContinuations[pending.id] = cont
            self.pendingConsent = pending
        }
    }

    /// Called by the view layer when the user decides.
    func resolveConsent(_ id: UUID, allow: Bool) {
        pendingConsent = nil
        consentContinuations.removeValue(forKey: id)?.resume(returning: allow)
    }
}
