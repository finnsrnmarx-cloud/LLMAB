import SwiftUI
import LLMCore
import MediaKit
import UIKitOmega

/// One row in the conversation. User turns sit right-aligned with an
/// indigo-deep background; assistant turns sit left-aligned with a slim
/// aurora-gradient stripe on the leading edge. Assistant turns carry a
/// speaker button that feeds TTSService; an AuroraRing pulses while
/// speaking.
struct MessageBubble: View {
    @EnvironmentObject private var tts: TTSService
    let message: Message
    let isStreaming: Bool

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system, .tool:
            EmptyView()
        }
    }

    // MARK: - User

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.textContent)
                .font(.system(.body))
                .foregroundStyle(Midnight.mist)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Midnight.navy)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .textSelection(.enabled)
        }
    }

    // MARK: - Assistant

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(AuroraGradient.linear(.full, startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 6) {
                if message.textContent.isEmpty && isStreaming {
                    OmegaSpinner(size: 16)
                } else {
                    Text(message.textContent)
                        .font(.system(.body))
                        .foregroundStyle(Midnight.mist)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if !message.textContent.isEmpty && !isStreaming {
                        speakerButton
                    }
                }
            }
            .padding(.vertical, 2)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Speaker button

    private var speakerButton: some View {
        Button {
            if tts.isSpeaking {
                tts.stop()
            } else {
                tts.speak(message.textContent)
            }
        } label: {
            HStack(spacing: 6) {
                if tts.isSpeaking {
                    AuroraRing(size: 12, lineWidth: 1.5, state: .running)
                } else {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 11))
                }
                Text(tts.isSpeaking ? "stop" : "speak")
                    .font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(Midnight.fog)
        }
        .buttonStyle(.plain)
        .help("Read this response with AVSpeechSynthesizer")
    }
}
