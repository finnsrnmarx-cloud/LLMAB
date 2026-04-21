import SwiftUI
import MediaKit
import UIKitOmega

/// Press-to-talk dictation surface. Holds a DictationService, streams live
/// partial transcriptions into its own buffer, and on stop populates the
/// shared ChatViewModel's composer (optionally auto-submitting).
struct DictateView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var chat: ChatViewModel
    @StateObject private var dictation = DictationService()

    @State private var liveText: String = ""
    @State private var streamingTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var autoSend: Bool = true

    var body: some View {
        VStack(spacing: 20) {
            header

            Spacer()

            transcriptPanel

            Spacer()

            bigMicButton
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { stop() }
    }

    // MARK: - Panels

    private var header: some View {
        HStack(spacing: 10) {
            if dictation.isListening {
                AuroraRing(size: 18, lineWidth: 2, state: .running)
                Text("listening")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Midnight.mist)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundStyle(Midnight.fog)
                Text("press and hold ω to dictate")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            }
            Spacer()
            Toggle("auto-send", isOn: $autoSend)
                .toggleStyle(.switch)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Midnight.fog)
        }
        .padding(.top, 4)
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let err = errorMessage {
                HStack(spacing: 8) {
                    AuroraRing(size: 16, lineWidth: 2, state: .failure)
                    Text(err)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Midnight.fog)
                }
            }
            Text(liveText.isEmpty ? "your words appear here" : liveText)
                .font(.system(.title3, design: .default))
                .foregroundStyle(liveText.isEmpty ? Midnight.fog : Midnight.mist)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(Midnight.abyss)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AuroraGradient.linear(.full),
                        lineWidth: dictation.isListening ? 1.5 : 0.5)
                .opacity(dictation.isListening ? 0.8 : 0.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var bigMicButton: some View {
        Button {
            // Tap toggles — press to start, press again to stop.
            if dictation.isListening {
                stopAndSubmit()
            } else {
                start()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Midnight.indigoDeep)
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(AuroraGradient.angular(.full), lineWidth: 3)
                    .frame(width: 96, height: 96)
                    .opacity(dictation.isListening ? 1 : 0.55)
                OmegaMark(size: 36, animated: dictation.isListening)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(dictation.isListening ? "stop dictation" : "start dictation"))
    }

    // MARK: - Control

    private func start() {
        errorMessage = nil
        liveText = ""
        streamingTask = Task { @MainActor in
            do {
                for try await text in dictation.startDictation() {
                    liveText = text
                }
                stopAndSubmit()
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    private func stop() {
        streamingTask?.cancel()
        streamingTask = nil
        dictation.stop()
    }

    private func stopAndSubmit() {
        dictation.stop()
        let text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chat.input = text
        if autoSend {
            chat.send()
            liveText = ""
        }
    }
}
