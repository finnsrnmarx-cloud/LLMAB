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

    /// Images queued to accompany the next user turn (displayed as chips
    /// above the composer). Cleared on send or via `removeAttachment`.
    @Published var pendingAttachments: [ImageAttachment] = []

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
        let hasAttachments = !pendingAttachments.isEmpty
        guard (!prompt.isEmpty || hasAttachments), !isStreaming else { return }

        var parts: [ContentPart] = []
        for attachment in pendingAttachments {
            parts.append(.image(attachment.data, mimeType: attachment.mimeType))
        }
        if !prompt.isEmpty {
            parts.append(.text(prompt))
        }

        let userTurn = Message(role: .user, parts: parts)
        let assistantTurn = Message.assistant("")
        turns.append(userTurn)
        turns.append(assistantTurn)

        input = ""
        pendingAttachments = []
        lastError = nil

        streamingTask = Task { [weak self] in
            await self?.runStream(for: assistantTurn.id)
        }
    }

    /// Queue an image for the next send. The image is decoded into raw bytes
    /// in the requested mimeType so the runtime adapter can pass it straight
    /// through. Rejects silently (with lastError) if the active model can't
    /// accept images.
    func attachImage(data: Data, mimeType: String, filename: String? = nil) async {
        guard let store else { return }
        if let resolved = await store.selected, !resolved.info.capabilities.imageIn {
            lastError = "\(resolved.info.displayName) does not accept images"
            return
        }
        pendingAttachments.append(ImageAttachment(
            data: data,
            mimeType: mimeType,
            filename: filename
        ))
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
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
