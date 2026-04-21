import ArgumentParser
import Foundation
import LLMCore
import ModelRegistry

struct ModelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "List every local model the installed runtimes expose."
    )

    @Flag(name: .shortAndLong, help: "Emit machine-readable JSON instead of the aurora table.")
    var json: Bool = false

    func run() async throws {
        let registry = ModelRegistry()
        let snapshot = await registry.scan()

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot.models)
            FileHandle.standardOutput.write(data)
            print()
            return
        }

        print(Style.banner("models"))
        print(Style.muted("scanned \(snapshot.runtimes.count) runtime(s) at \(snapshot.scannedAt)"))
        for rt in snapshot.runtimes {
            let icon = rt.available ? Style.success("●") : Style.muted("○")
            let err = rt.error.map { " \(Style.error($0))" } ?? ""
            print("  \(icon) \(Style.accent(rt.displayName)) \(Style.muted("(\(rt.modelCount) models)"))\(err)")
        }
        print()

        if snapshot.models.isEmpty {
            print(Style.muted("no local models yet — try: \(Style.accent("llmab pull gemma-4:e4b"))"))
            return
        }

        let nameWidth = max(18, snapshot.models.map { $0.displayName.count }.max() ?? 18)
        let idWidth   = max(18, snapshot.models.map { $0.id.count }.max() ?? 18)

        print("  \(pad("MODEL", nameWidth))  \(pad("ID", idWidth))  \(pad("SIZE", 8))  CAPS")
        for m in snapshot.models {
            let loadedMark = m.isLoaded ? Style.success("*") : " "
            let caps = capabilityBadges(m.capabilities)
            print("  \(loadedMark)\(pad(m.displayName, nameWidth - 1))  \(Style.muted(pad(m.id, idWidth)))  \(pad(Style.bytes(m.sizeBytes), 8))  \(caps)")
        }
    }

    private func capabilityBadges(_ caps: ModelCapabilities) -> String {
        var parts: [String] = []
        if caps.imageIn { parts.append(Style.cyan + "img" + Style.reset) }
        if caps.audioIn { parts.append(Style.green + "aud" + Style.reset) }
        if caps.videoIn { parts.append(Style.violet + "vid" + Style.reset) }
        if caps.imageOut { parts.append(Style.magenta + "->img" + Style.reset) }
        if caps.toolUse { parts.append(Style.amber + "tool" + Style.reset) }
        if caps.thinking { parts.append(Style.rose + "think" + Style.reset) }
        parts.append(Style.muted("\(caps.contextTokens / 1000)K"))
        return parts.joined(separator: " ")
    }

    /// Pad `s` to `width` visible columns. Any ANSI escape sequence
    /// (`ESC [ ... m`) is skipped when counting width.
    private func pad(_ s: String, _ width: Int) -> String {
        let visibleCount = Style.visibleWidth(s)
        let padding = max(0, width - visibleCount)
        return s + String(repeating: " ", count: padding)
    }
}
