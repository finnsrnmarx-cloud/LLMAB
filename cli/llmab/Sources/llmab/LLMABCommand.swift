import ArgumentParser
import Foundation
import LLMCore

@main
struct LLMABCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "llmab",
        abstract: "ω — local-LLM CLI for macOS. Gemma 4 first, Ollama by default.",
        version: LLMCore.version,
        subcommands: [
            ModelsCommand.self,
            PullCommand.self,
            ChatCommand.self
        ],
        defaultSubcommand: ModelsCommand.self
    )
}
