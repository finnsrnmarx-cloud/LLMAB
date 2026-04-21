import ArgumentParser
import Foundation
import LLMCore
import ModelRegistry

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "One-shot chat with a local model. Streams tokens to stdout."
    )

    @Option(name: [.short, .long], help: "Model id, e.g. 'gemma-4:e4b' or 'ollama:gemma-4:e4b'.")
    var model: String

    @Option(name: [.short, .long], help: "Optional system prompt.")
    var system: String?

    @Option(name: [.customShort("t"), .long], help: "Sampling temperature (0–2). Default: 0.7.")
    var temperature: Double = 0.7

    @Option(name: [.customShort("n"), .long], help: "Max tokens. Default: 2048.")
    var maxTokens: Int = 2048

    @Argument(parsing: .remaining,
              help: "Prompt text. If omitted, reads from stdin.")
    var prompt: [String] = []

    func run() async throws {
        let promptText = try resolvePrompt()

        let registry = ModelRegistry()
        _ = await registry.scan()

        // Try full-id first, then fall back to raw-name match within any runtime.
        let (runtime, info) = try await resolveModel(in: registry)

        print(Style.banner("chat"))
        print(Style.muted("model: \(Style.accent(info.displayName)) via \(runtime.displayName)"))
        if !info.capabilities.textOut {
            print(Style.error("this model does not emit text — chat is not supported"))
            throw ExitCode.failure
        }
        print()

        var messages: [Message] = []
        if let s = system { messages.append(.system(s)) }
        messages.append(.user(promptText))

        let request = ChatRequest(
            modelId: info.id,
            messages: messages,
            sampling: SamplingConfig(
                temperature: temperature,
                maxTokens: maxTokens
            ),
            stream: true
        )

        // Prompt prefix marking the assistant turn.
        FileHandle.standardOutput.write(Data("\(Style.omega) ".utf8))

        var usage: ChatChunk.Usage?
        for try await chunk in runtime.chat(request) {
            switch chunk {
            case .text(let t):
                FileHandle.standardOutput.write(Data(t.utf8))
            case .toolCall(let call):
                let argStr = String(data: call.argumentsJSON, encoding: .utf8) ?? "{}"
                FileHandle.standardOutput.write(
                    Data("\n\(Style.amber)[tool-call \(call.toolId) \(argStr)]\(Style.reset)\n".utf8)
                )
            case .finish(_, let u):
                usage = u
            }
        }
        print()  // newline after last token

        if let u = usage {
            let tokens = u.totalTokens.map(String.init) ?? "?"
            print(Style.muted("— \(tokens) tokens"))
        }
    }

    // MARK: - Helpers

    private func resolvePrompt() throws -> String {
        if !prompt.isEmpty { return prompt.joined(separator: " ") }
        // Read stdin until EOF.
        let stdin = FileHandle.standardInput
        let data = stdin.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("provide a prompt as arguments or via stdin")
        }
        return text
    }

    private func resolveModel(in registry: ModelRegistry) async throws -> (any LLMRuntime, ModelInfo) {
        // Exact id match first.
        if let hit = await registry.resolve(modelId: model) {
            return (hit.runtime, hit.info)
        }

        // Fall back to raw-name match across runtimes.
        let snap = await registry.cached()
        guard let snap = snap else {
            throw ValidationError("registry has no snapshot — run `llmab models` first")
        }
        if let byRaw = snap.models.first(where: { $0.rawName == model }) {
            if let rt = await registry.runtime(id: byRaw.runtimeId) {
                return (rt, byRaw)
            }
        }
        throw ValidationError("no installed model matches '\(model)'. Try `llmab models`.")
    }
}
