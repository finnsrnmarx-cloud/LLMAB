import SwiftUI
import UIKitOmega

/// Renderer for a single transcript entry in the Agents tab.
struct AgentTranscriptRow: View {
    let turn: AgentsTabViewModel.Turn

    var body: some View {
        switch turn.kind {
        case .assistant(let text):
            assistant(text: text)
        case .toolCall(let toolId, let args):
            toolCall(id: toolId, args: args)
        case .toolResult(let toolId, let output):
            toolResult(id: toolId, output: output)
        case .toolError(let toolId, let message):
            toolError(id: toolId, message: message)
        case .note(let text):
            note(text: text)
        }
    }

    // MARK: - Rows

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
        }
    }

    private func toolCall(id: String, args: Data) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AuroraRing(size: 12, lineWidth: 1.5, state: .running)
                Text("→ \(id)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Midnight.mist)
            }
            Text(pretty(json: args))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Midnight.fog)
                .lineLimit(8)
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

    private func toolResult(id: String, output: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AuroraRing(size: 12, lineWidth: 1.5, state: .success)
                Text("← \(id)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Midnight.mist)
            }
            Text(output)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Midnight.mist)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Midnight.abyss)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func toolError(id: String, message: String) -> some View {
        HStack(spacing: 8) {
            AuroraRing(size: 12, lineWidth: 1.5, state: .failure)
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

    // MARK: - Helpers

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
