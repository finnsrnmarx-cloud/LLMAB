import ArgumentParser
import Foundation
import LLMCore
import ModelRegistry
import RuntimeOllama

struct PullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Download a model into a local runtime (Ollama by default)."
    )

    @Argument(help: "Runtime-qualified name, e.g. 'gemma-4:e4b' (Ollama) or 'ollama:gemma-4:e4b'.")
    var model: String

    @Option(name: .long, help: "Runtime id. Default: ollama.")
    var runtime: String = RuntimeOllama.id

    func run() async throws {
        let registry = ModelRegistry()
        _ = await registry.scan()
        guard let rt = await registry.runtime(id: runtime) else {
            throw ExitCode.validationFailure
        }

        // Accept both bare and prefixed names; send the bare name onwards.
        let rawName: String
        if model.hasPrefix("\(runtime):") {
            rawName = String(model.dropFirst(runtime.count + 1))
        } else {
            rawName = model
        }

        print(Style.banner("pull"))
        print(Style.muted("runtime: \(rt.displayName)"))
        print(Style.muted("model:   \(Style.accent(rawName))"))
        print()

        let stream = rt.pullModel(rawName)
        var lastStatus = ""
        var lastFraction: Double = -1

        for try await progress in stream {
            if progress.status != lastStatus {
                print("  \(Style.accent(progress.status))")
                lastStatus = progress.status
            }
            if let f = progress.fraction, abs(f - lastFraction) > 0.01 {
                drawBar(fraction: f,
                        downloaded: progress.downloadedBytes,
                        total: progress.totalBytes)
                lastFraction = f
            }
            if progress.completed {
                print("\n\(Style.success("✓ complete"))")
            }
        }
    }

    /// Aurora-themed progress bar. Rendered with \r so it rewrites in place.
    private func drawBar(fraction: Double, downloaded: Int64?, total: Int64?) {
        let columns = 40
        let filled = Int((fraction * Double(columns)).rounded())
        let empty = columns - filled

        let stops = [Style.rose, Style.orange, Style.amber,
                     Style.green, Style.cyan, Style.violet, Style.magenta]
        var bar = ""
        for i in 0..<filled {
            let stop = stops[min(stops.count - 1, (i * stops.count) / columns)]
            bar += stop + "█"
        }
        bar += Style.reset
        bar += Style.muted(String(repeating: "░", count: empty))

        let pct = String(format: "%3d%%", Int(fraction * 100))
        let sizeStr = "\(Style.bytes(downloaded)) / \(Style.bytes(total))"

        FileHandle.standardError.write(
            Data("\r  \(bar) \(pct)  \(Style.muted(sizeStr))".utf8)
        )
    }
}
