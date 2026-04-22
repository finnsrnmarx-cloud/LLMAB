import SwiftUI
import LLMCore
import ModelRegistry
import RuntimeOllama
import RuntimeLlamaCpp
import MediaKit
import UIKitOmega

/// Cmd-, preferences pane. Three sections:
///   1. Runtimes — per-runtime availability row with AuroraRing
///   2. Models — grouped model picker with capability badges
///   3. Voice — AVSpeechSynthesizer voice picker that previews through
///      TTSService on change
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var tts: TTSService

    @State private var pullModelName: String = "gemma-4:26b-a4b"
    @State private var pullProgress: PullProgress?
    @State private var isPulling: Bool = false
    @State private var pullError: String?
    // Voice selection is persisted on the store so the choice survives
    // across tab switches and launches.

    private var voices: [String] { TTSService.availableVoices() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                runtimesSection
                LocalGGUFsSection(controller: store.llamaServer) {
                    // When the server state transitions, re-scan so the
                    // adapter's newly-served model shows up in Models.
                    Task { await store.refresh() }
                }
                modelsSection
                pullSection
                voiceSection
            }
            .padding(28)
        }
        .frame(minWidth: 640, minHeight: 560)
        .background(Midnight.midnight)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            OmegaMark(size: 26, animated: true)
            Text("ω settings")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(Midnight.mist)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                HStack(spacing: 6) {
                    if store.isScanning {
                        AuroraRing(size: 12, lineWidth: 1.5, state: .running)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    Text("rescan")
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundStyle(Midnight.mist)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Midnight.indigoDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AuroraGradient.linear(.full), lineWidth: 0.8)
                        .opacity(0.6)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.isScanning)
        }
    }

    // MARK: - Runtimes

    private var runtimesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("runtimes")
            if let snap = store.snapshot {
                ForEach(snap.runtimes) { rt in
                    runtimeRow(rt)
                }
            } else {
                Text("scan pending…")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            }
        }
    }

    private func runtimeRow(_ rt: ModelRegistry.RuntimeStatus) -> some View {
        HStack(spacing: 10) {
            AuroraRing(size: 14, lineWidth: 1.5,
                       state: rt.available ? .success : .idle)
            Text(rt.displayName)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(Midnight.mist)
            Text("(\(rt.modelCount) models)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Midnight.fog)
            Spacer()
            if let err = rt.error {
                Text(err)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Midnight.abyss)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Models

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("models")
            if let snap = store.snapshot, !snap.models.isEmpty {
                ForEach(snap.models) { m in
                    modelRow(m)
                }
            } else {
                Text("no local models — start a runtime (Ollama / llama-server / mlx_lm) and hit rescan, or pull via the form below")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            }
        }
    }

    private func modelRow(_ m: ModelInfo) -> some View {
        let isSelected = store.selectedModelId == m.id
        return Button {
            store.selectedModelId = m.id
        } label: {
            HStack(spacing: 10) {
                if isSelected {
                    OmegaMark(size: 14, animated: true)
                } else {
                    Spacer().frame(width: 14)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(m.displayName)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Midnight.mist)
                        Text(m.runtimeId)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Midnight.fog)
                    }
                    capabilityBadges(for: m.capabilities)
                }
                Spacer()
                if m.isLoaded {
                    Text("loaded")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Midnight.fog)
                }
            }
            .padding(10)
            .background(isSelected ? Midnight.indigoDeep : Midnight.abyss)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AuroraGradient.linear(.full),
                            lineWidth: isSelected ? 1 : 0)
                    .opacity(isSelected ? 0.6 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func capabilityBadges(for c: ModelCapabilities) -> some View {
        HStack(spacing: 6) {
            if c.imageIn  { badge("img",   style: Midnight.navy) }
            if c.audioIn  { badge("aud",   style: Midnight.navy) }
            if c.videoIn  { badge("vid",   style: Midnight.navy) }
            if c.imageOut { badge("→img",  style: Midnight.navy) }
            if c.toolUse  { badge("tool",  style: Midnight.navy) }
            if c.thinking { badge("think", style: Midnight.navy) }
            badge("\(c.contextTokens / 1000)K", style: Midnight.navy)
        }
    }

    private func badge(_ text: String, style: Color) -> some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced).weight(.semibold))
            .foregroundStyle(Midnight.mist)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(style)
            .clipShape(Capsule())
    }

    // MARK: - Pull

    private var pullSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("pull a model (Ollama)")
            Text("Only applies to Ollama. For llama.cpp, start `llama-server` against your GGUF and hit rescan — the model auto-appears above. For MLX, place weights under ~/.cache/huggingface/hub/models--mlx-community--*.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Midnight.fog)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("gemma-4:26b-a4b", text: $pullModelName)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Midnight.mist)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Midnight.indigoDeep)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button {
                    Task { await startPull() }
                } label: {
                    HStack(spacing: 6) {
                        if isPulling {
                            OmegaSpinner(size: 14)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 11))
                        }
                        Text(isPulling ? "pulling" : "pull")
                            .font(.system(.caption2, design: .monospaced))
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
                .disabled(isPulling || pullModelName.isEmpty)
            }
            if let p = pullProgress {
                pullProgressBar(p)
            }
            if let err = pullError {
                Text(err)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            }
        }
    }

    private func pullProgressBar(_ p: PullProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(p.status)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Midnight.fog)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Midnight.abyss)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AuroraGradient.linear(.full))
                        .frame(width: geo.size.width * CGFloat(p.fraction ?? 0),
                               height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func startPull() async {
        pullError = nil
        pullProgress = nil
        isPulling = true
        defer { isPulling = false }
        let runtime = OllamaRuntime()
        guard await runtime.isAvailable() else {
            pullError = "Ollama daemon is not running on 127.0.0.1:11434"
            return
        }
        do {
            for try await progress in runtime.pullModel(pullModelName) {
                pullProgress = progress
            }
            await store.refresh()
        } catch {
            pullError = String(describing: error)
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("tts voice (AVSpeechSynthesizer)")
            if voices.isEmpty {
                Text("no system voices installed")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            } else {
                Picker("voice", selection: $store.ttsVoiceIdentifier) {
                    Text("auto (best British voice installed)").tag(String?.none)
                    ForEach(voices, id: \.self) { v in
                        Text(TTSService.label(for: v)).tag(String?.some(v))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: store.ttsVoiceIdentifier) { _, new in
                    tts.speak("Hello — this is ω. I read the room, and the room reads me back.",
                              voice: new)
                }
                Text("Tip: for the nicest voice, open System Settings → Accessibility → Spoken Content → System Voice → English (UK), then tap Customize and download a Premium voice (Siri Voice 2 or 4 on Apple Silicon).")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Section title

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced).weight(.semibold))
            .foregroundStyle(AuroraGradient.linear(.full))
            .textCase(.uppercase)
    }
}
