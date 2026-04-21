import SwiftUI
import LLMCore
import MediaKit
import UIKitOmega
#if canImport(AppKit)
import AppKit
#endif

/// One row in the conversation. User turns render image attachments above the
/// text bubble; assistant turns carry an aurora leading stripe and a TTS
/// speaker button.
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
            VStack(alignment: .trailing, spacing: 6) {
                if !userImages.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(userImages.enumerated()), id: \.offset) { _, data in
                            thumbnail(data: data)
                        }
                    }
                }
                if !message.textContent.isEmpty {
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
        }
    }

    private var userImages: [Data] {
        message.parts.compactMap { part in
            if case .image(let data, _) = part { return data } else { return nil }
        }
    }

    @ViewBuilder
    private func thumbnail(data: Data) -> some View {
        #if canImport(AppKit)
        if let ns = NSImage(data: data) {
            Image(nsImage: ns)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AuroraGradient.linear(.full), lineWidth: 1)
                        .opacity(0.4)
                )
        } else {
            fallbackThumb
        }
        #else
        fallbackThumb
        #endif
    }

    private var fallbackThumb: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Midnight.indigoDeep)
            .frame(width: 120, height: 120)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(Midnight.fog)
            )
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
