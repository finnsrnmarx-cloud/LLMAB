import SwiftUI
import UIKitOmega
import MediaKit

/// Video tab — live camera + mic → VLM → TTS. Turn-based: hold the ω button
/// to talk, release to send the latest frame + what you said. Full
/// continuous mode is a later iteration.
struct VideoTab: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var tts: TTSService
    @StateObject private var vm = VideoTabViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("Video",
                      subtitle: "live · aurora-full · requires 26B / 31B",
                      palette: .full,
                      showSpinner: vm.isReplying)

            if vm.isSessionRunning {
                runningBody
            } else {
                startGate
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            vm.bind(store: store, tts: tts)
        }
        .onDisappear { vm.stopSession() }
    }

    // MARK: - Pre-start gate

    private var startGate: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                OmegaMark(size: 20, animated: true)
                Text("live video chat")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Midnight.mist)
            }
            Text("Hold the ω button to speak; release and ω replies about what it sees. Gemma 4 26B and 31B accept video frames; E-series does not.")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Midnight.fog)
            Button {
                Task { await vm.startSession() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "video.circle")
                    Text("start camera")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                }
                .foregroundStyle(Midnight.mist)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Midnight.indigoDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AuroraGradient.linear(.full), lineWidth: 0.8)
                        .opacity(0.6)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            if let err = vm.error {
                Text(err)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            }
        }
        .padding(24)
    }

    // MARK: - Running body

    private var runningBody: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                VideoPreview(service: vm.capture)
                    .background(Color.black)
                if vm.isSessionRunning {
                    HStack(spacing: 6) {
                        OmegaSpinner(size: 14)
                        Text("live")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Midnight.mist)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Midnight.void.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(12)
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(AuroraGradient.linear(.full).opacity(0.25))

            sidebar
                .frame(width: 320)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(vm.transcript) { ex in
                            exchangeRow(ex).id(ex.id)
                        }
                        if vm.isListening {
                            liveRow
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: vm.transcript.count) { _, _ in
                    if let last = vm.transcript.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            Divider().overlay(AuroraGradient.linear(.full).opacity(0.25))
            controlBar
        }
        .background(Midnight.abyss)
    }

    private func exchangeRow(_ ex: VideoTabViewModel.Exchange) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("you · \(ex.user)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Midnight.fog)
            Text(ex.assistant)
                .font(.system(.caption))
                .foregroundStyle(Midnight.mist)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var liveRow: some View {
        HStack(alignment: .top, spacing: 6) {
            AuroraRing(size: 12, lineWidth: 1.5, state: .running)
            Text(vm.liveTranscription.isEmpty ? "listening…" : vm.liveTranscription)
                .font(.system(.caption))
                .foregroundStyle(Midnight.mist)
        }
    }

    private var controlBar: some View {
        HStack {
            Button(action: vm.stopSession) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(Midnight.fog)
                    .padding(6)
                    .background(Midnight.indigoDeep)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Spacer()

            Button {
                if vm.isListening { vm.stopListening() } else { vm.startListening() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Midnight.indigoDeep)
                        .frame(width: 68, height: 68)
                    Circle()
                        .strokeBorder(AuroraGradient.angular(.full), lineWidth: 3)
                        .frame(width: 68, height: 68)
                        .opacity(vm.isListening ? 1 : 0.55)
                    OmegaMark(size: 28, animated: vm.isListening)
                }
            }
            .buttonStyle(.plain)
            .disabled(vm.isReplying)

            Spacer()
            if let err = vm.error {
                Text(err)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
                    .lineLimit(2)
            }
        }
        .padding(12)
    }
}
