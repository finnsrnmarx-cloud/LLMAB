import SwiftUI
import UIKitOmega

/// Primary tab — default on launch. Sub-modes share a single ChatViewModel
/// so dictation can submit through the same pipeline as typing.
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
    @StateObject private var chat = ChatViewModel()
    @EnvironmentObject private var store: AppStore

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
                    ChatConversationView(chat: chat)
                case .dictate:
                    DictateView(chat: chat)
                case .live:
                    PlaceholderCard(
                        title: "Ships later in chunk 9.5 / 13",
                        message: "Continuous live conversation: press once, the app listens, transcribes, replies, and speaks — then loops. Uses the same DictationService + TTSService; requires audio-capable model (E2B / E4B).",
                        palette: .full
                    )
                    Spacer()
                case .image:
                    // Image upload is integrated into the composer in every
                    // mode; the dedicated `.image` mode is a nudge / affordance
                    // that routes the user to the same conversation view with
                    // a hint banner.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 14))
                                .foregroundStyle(AuroraGradient.linear(.full))
                            Text("tap the paperclip in the composer to attach images")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Midnight.fog)
                        }
                        .padding(.horizontal, 24)
                        ChatConversationView(chat: chat)
                    }
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
        .onAppear { chat.bind(to: store) }
    }
}
