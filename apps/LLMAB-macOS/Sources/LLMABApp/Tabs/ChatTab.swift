import SwiftUI
import UIKitOmega

/// Primary tab — default on launch. Sub-modes live inside a segmented picker
/// (Live, Chat, Dictate, Image, Create-image). Real wiring starts in chunk 8.
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

            PlaceholderCard(
                title: "Ships in chunk 8–10",
                body: "Text streaming → Gemma 4 via Ollama (chunk 8). Dictate + TTS via Apple Speech + AVSpeechSynthesizer (chunk 9). Image+text upload (chunk 10). Create-image gates on a detected diffusion model (chunk 15).",
                palette: .full
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
