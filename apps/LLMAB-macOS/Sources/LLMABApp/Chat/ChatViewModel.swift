import Foundation
import LLMCore
import ModelRegistry
import SwiftUI

/// State for a single text-mode chat session: the running message list, the
/// composer, and the streaming task.
@MainActor
final class ChatViewModel: ObservableObject {

    /// Turns as they appear in the UI. `.assistant` messages are mutated in
    /// place while streaming.
    @Published private(set) var turns: [Message] = []

    /// Composer text.
    @Published var input: String = ""

    /// True while any token / tool-call is arriving.
    @Published private(set) var isStreaming: Bool = false

    /// If the most recent send errored, this is set — the UI renders an
    /// AuroraRing in the .failure state beside the offending turn.
    @Published private(set) var lastError: String?

    private var streamingTask: Task<Void, Never>?
    private weak var store: AppStore?

    func bind(to store: AppStore) { self.store = store }

    // MARK: - Send

    func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming else { return }
        input = ""
        lastError = nil

        let userTurn = Message.user(prompt)
        let assistantTurn = Message.assistant("")
        turns.append(userTurn)
        turns.append(assistantTurn)

        streamingTask = Task { [weak self] in
            await self?.runStream(for: assistantTurn.id)
        }
    }

    func cancel() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
    }

    // MARK: - Stream

    private func runStream(for assistantId: UUID) async {
        guard let store else { return }
        guard let resolved = await store.selected else {
            fail(assistantId: assistantId, message: "no model selected")
            return
        }
        let (runtime, info) = resolved

        guard info.capabilities.textOut else {
            fail(assistantId: assistantId, message: "\(info.displayName) does not emit text")
            return
        }

        let request = ChatRequest(
            modelId: info.id,
            messages: messagesForRequest(),
            sampling: .balanced,
            stream: true
        )

        isStreaming = true
        defer { isStreaming = false }

        do {
            for try await chunk in runtime.chat(request) {
                if Task.isCancelled { return }
                switch chunk {
                case .text(let delta):
                    append(to: assistantId, text: delta)
                case .toolCall:
                    // Tool calls are a chunk-12 concern; ignore in text chat.
                    break
                case .finish:
                    break
                }
            }
        } catch {
            fail(assistantId: assistantId, message: String(describing: error))
        }
    }

    private func messagesForRequest() -> [Message] {
        // Drop the final empty assistant placeholder before sending.
        if turns.last?.role == .assistant, turns.last?.textContent.isEmpty == true {
            return Array(turns.dropLast())
        }
        return turns
    }

    // MARK: - Mutation helpers

    private func append(to id: UUID, text: String) {
        guard let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        let existing = turns[idx].textContent
        turns[idx] = Message(id: id, role: .assistant, parts: [.text(existing + text)])
    }

    private func fail(assistantId: UUID, message: String) {
        lastError = message
        // Replace the empty assistant turn body with the error so the UI has
        // something to render beside the failure ring.
        if let idx = turns.firstIndex(where: { $0.id == assistantId }) {
            turns[idx] = Message(id: assistantId, role: .assistant,
                                 parts: [.text("⚠️ \(message)")])
        }
    }

    // MARK: - Reset

    func newConversation() {
        cancel()
        turns = []
        input = ""
        lastError = nil
    }
}
