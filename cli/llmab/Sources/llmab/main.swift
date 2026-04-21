import ArgumentParser
import Foundation
import LLMCore

@main
struct LLMAB: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "llmab",
        abstract: "ω — local-LLM CLI for macOS (Gemma 4 first).",
        version: LLMCore.version,
        subcommands: []
    )

    mutating func run() throws {
        print("ω llmab \(LLMCore.version) — scaffold. Subcommands arrive in chunk 6.")
    }
}
