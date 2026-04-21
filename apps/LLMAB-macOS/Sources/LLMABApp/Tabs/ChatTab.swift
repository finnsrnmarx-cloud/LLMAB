import SwiftUI
import UIKitOmega

/// Primary tab — default on launch. Sub-modes live inside a segmented picker
/// (Live, Chat, Dictate, Image, Create-image). Typed Chat is live in chunk 8;
/// remaining sub-modes come online in chunks 9–15.
struct ChatTab: View {
    enum Mode: String, CaseIterable, Identifiable {
        case live = "Live"
        case chat = "Chat"
        case dictate = "Dictate"
        case image = "Image"
        case create = "Create"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .chat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TabHeader("Chat",
                      subtitle: "primary · aurora-full",
                      palette: .full)

            Picker("mode", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            Group {
                switch mode {
                case .chat:
                    ChatConversationView()
                case .live:
                    PlaceholderCard(
                        title: "Ships in chunk 9",
                        message: "Live conversation: continuous mic → Gemma 4 E → AVSpeechSynthesizer out. Requires an audio-capable model (E2B / E4B).",
                        palette: .full
                    )
                    Spacer()
                case .dictate:
                    PlaceholderCard(
                        title: "Ships in chunk 9",
                        message: "Press-to-talk dictation via Apple Speech framework. Transcribed text lands in the composer; you edit and send.",
                        palette: .full
                    )
                    Spacer()
                case .image:
                    PlaceholderCard(
                        title: "Ships in chunk 10",
                        message: "Upload an image, ask about it. Any Gemma 4 variant accepts image-in.",
                        palette: .full
                    )
                    Spacer()
                case .create:
                    PlaceholderCard(
                        title: "Feature-gated",
                        message: "Create-image is hidden until a diffusion model (FLUX / SDXL / Stable Diffusion) is detected. Install one via Ollama and return to Settings to enable.",
                        palette: .full
                    )
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
