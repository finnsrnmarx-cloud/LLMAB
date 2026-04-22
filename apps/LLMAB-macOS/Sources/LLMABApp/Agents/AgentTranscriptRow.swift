import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import UIKitOmega

/// Renderer for a single transcript entry in the Agents tab. Tool-call and
/// tool-result rows are collapsible, numbered (step 1 / 2 / …), and expose a
/// copy-to-clipboard button on their long bodies.
struct AgentTranscriptRow: View {
    let turn: AgentsTabViewModel.Turn

    /// Monotonic step number to display on tool rows, or nil to hide the chip.
    let stepNumber: Int?

    init(turn: AgentsTabViewModel.Turn, stepNumber: Int? = nil) {
        self.turn = turn
        self.stepNumber = stepNumber
    }

    @State private var isExpanded: Bool = true

    var body: some View {
        switch turn.kind {
        case .assistant(let text):
            assistant(text: text)
        case .toolCall(let toolId, let args):
            ToolCallCard(
                id: toolId,
                argsJSON: args,
                stepNumber: stepNumber
            )
        case .toolResult(let toolId, let output):
            ToolResultCard(
                id: toolId,
                output: output,
                stepNumber: stepNumber
            )
        case .toolError(let toolId, let message):
            toolError(id: toolId, message: message)
        case .note(let text):
            note(text: text)
        }
    }

    // MARK: - Assistant / note / error rows

    private func assistant(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(AuroraGradient.linear(.full, startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
                .clipShape(Capsule())
            Text(text)
                .font(.system(.body))
                .foregroundStyle(Midnight.mist)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            CopyButton(text: text)
                .opacity(text.isEmpty ? 0 : 0.7)
        }
    }

    private func toolError(id: String, message: String) -> some View {
        HStack(spacing: 8) {
            AuroraRing(size: 12, lineWidth: 1.5, state: .failure)
            if let n = stepNumber { stepChip(n) }
            Text("\(id) failed — \(message)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Midnight.fog)
        }
        .padding(10)
        .background(Midnight.abyss)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func note(text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Midnight.fog)
            .padding(.horizontal, 4)
    }

    // Not private so the sub-cards reuse it.
    @ViewBuilder
    fileprivate static func stepChip(_ n: Int) -> some View {
        Text("#\(n)")
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .foregroundStyle(Midnight.mist)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Midnight.indigoDeep)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AuroraGradient.linear(.full), lineWidth: 0.5)
                    .opacity(0.45)
            )
    }

    // Instance call-site uses the static.
    @ViewBuilder
    private func stepChip(_ n: Int) -> some View {
        Self.stepChip(n)
    }
}

// MARK: - Tool-call / tool-result cards

private struct ToolCallCard: View {
    let id: String
    let argsJSON: Data
    let stepNumber: Int?

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Midnight.fog)
                    AuroraRing(size: 12, lineWidth: 1.5, state: .running)
                    if let n = stepNumber { AgentTranscriptRow.stepChip(n) }
                    Text("→ \(id)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Midnight.mist)
                    Spacer()
                    CopyButton(text: pretty(json: argsJSON))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(pretty(json: argsJSON))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)
            }
        }
        .padding(10)
        .background(Midnight.abyss)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AuroraGradient.linear(.full), lineWidth: 0.6)
                .opacity(0.35)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func pretty(json data: Data) -> String {
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8)
        else {
            return String(data: data, encoding: .utf8) ?? "<binary args>"
        }
        return text
    }
}

private struct ToolResultCard: View {
    let id: String
    let output: String
    let stepNumber: Int?

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Midnight.fog)
                    AuroraRing(size: 12, lineWidth: 1.5, state: .success)
                    if let n = stepNumber { AgentTranscriptRow.stepChip(n) }
                    Text("← \(id)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Midnight.mist)
                    Text("· \(lineCountLabel)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Midnight.fog)
                    Spacer()
                    CopyButton(text: output)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(output)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.mist)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)
            }
        }
        .padding(10)
        .background(Midnight.abyss)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var lineCountLabel: String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).count
        let chars = output.count
        if lines > 1 {
            return "\(lines) lines · \(chars) chars"
        }
        return "\(chars) chars"
    }
}

// MARK: - Copy button

/// Tiny inline "copy" control — `⌘ + dot` icon, 1-second "copied" checkmark.
struct CopyButton: View {
    let text: String
    @State private var copied: Bool = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(Midnight.fog)
                .frame(width: 22, height: 22)
                .background(Midnight.indigoDeep.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(copied ? "copied" : "copy")
        .accessibilityLabel(copied ? "copied" : "copy to clipboard")
    }

    private func copy() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) { copied = false }
            }
        }
    }
}
