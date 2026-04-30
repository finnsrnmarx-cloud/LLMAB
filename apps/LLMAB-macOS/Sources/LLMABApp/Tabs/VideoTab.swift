import SwiftUI
import UIKitOmega
import MediaKit
import LLMCore

/// Video tab — camera + mic → VLM → TTS. Snapshot talk is immediate; clip
/// mode captures near-20fps preview frames and then samples them according to
/// the selected model's video profile.
struct VideoTab: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var tts: TTSService
    @StateObject private var vm = VideoTabViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("Video",
                      subtitle: "live · aurora-full · any vision-capable model",
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
            Text("Tap ω for a camera snapshot, or use adaptive live for a short sampled clip. 20fps experimental is guarded and only runs on models that advertise high-rate video ingest.")
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
        VStack(spacing: 8) {
            // Countdown ribbon while watching.
            if vm.isWatching {
                HStack(spacing: 6) {
                    AuroraRing(size: 12, lineWidth: 1.5, state: .running)
                    Text("\(clipModeLabel) · \(String(format: "%.1f", vm.watchSecondsRemaining))s left")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Midnight.mist)
                    Spacer()
                }
            }

            clipModePicker
            visionFallbackPicker

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

                // Hold-to-talk — single snapshot
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
                .disabled(vm.isReplying || vm.isWatching)
                .help("snapshot of the current frame")

                // Clip capture — adaptive by default, guarded 20fps experiment.
                Button {
                    if vm.isWatching { vm.stopWatchEarly() } else { vm.startWatch() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: vm.isWatching ? "stop.circle" : "eye.circle")
                            .font(.system(size: 14))
                        Text(vm.isWatching ? "stop" : clipButtonLabel)
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    }
                    .foregroundStyle(Midnight.mist)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Midnight.indigoDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AuroraGradient.linear(.full), lineWidth: 0.8)
                            .opacity(vm.isWatching ? 0.9 : 0.55)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(vm.isReplying || vm.isListening)

                Spacer()
                if let err = vm.error {
                    Text(err)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Midnight.fog)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
    }

    private var clipModePicker: some View {
        Picker("video mode", selection: $vm.clipMode) {
            Text("adaptive live").tag(VideoTurnMode.adaptiveLive)
            Text("20fps experimental").tag(VideoTurnMode.experimental20FPS)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(vm.isReplying || vm.isListening || vm.isWatching)
        .help("Adaptive live captures near 20fps but sends selected keyframes. 20fps experimental sends a short high-rate window only if the model advertises support.")
    }

    private var visionFallbackPicker: some View {
        Group {
            if !selectedModelAcceptsFrames {
                HStack(spacing: 8) {
                    Text("selected model can't see frames")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Midnight.fog)
                    Spacer()
                    Menu("pick vision") {
                        ForEach(visionModels) { model in
                            Button(model.displayName) {
                                store.selectedModelId = model.id
                            }
                        }
                    }
                    .font(.system(.caption2, design: .monospaced))
                }
            }
            if vm.clipMode == .experimental20FPS {
                Text("20fps experimental may be slow and is blocked unless the selected model advertises high-rate video ingest.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var clipButtonLabel: String {
        switch vm.clipMode {
        case .snapshot:
            return "snapshot"
        case .adaptiveLive:
            return "adaptive live"
        case .experimental20FPS:
            return "20fps exp"
        }
    }

    private var clipModeLabel: String {
        switch vm.clipMode {
        case .snapshot:
            return "snapshot"
        case .adaptiveLive:
            return "adaptive live"
        case .experimental20FPS:
            return "20fps"
        }
    }

    private var selectedModelAcceptsFrames: Bool {
        guard let id = store.selectedModelId,
              let model = store.snapshot?.models.first(where: { $0.id == id }) else {
            return false
        }
        let profile = model.capabilities.videoProfile
        return model.capabilities.imageIn || profile.snapshot || profile.sampledClip || profile.nativeVideo
    }

    private var visionModels: [ModelInfo] {
        store.snapshot?.models.filter { model in
            let profile = model.capabilities.videoProfile
            return model.capabilities.imageIn || profile.snapshot || profile.sampledClip || profile.nativeVideo
        } ?? []
    }
}
