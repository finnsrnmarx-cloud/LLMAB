import SwiftUI
import RuntimeLlamaCpp
import UIKitOmega

/// Settings section that lists GGUF files found on disk and lets the user
/// start / stop a managed `llama-server` subprocess against any of them.
/// Observes `LlamaServerController` directly so state transitions
/// (`stopped → starting → running`) render live.
struct LocalGGUFsSection: View {
    @ObservedObject var controller: LlamaServerController
    /// Fires after the controller transitions to `.running` so the rest of
    /// Settings can re-scan (and the new model shows up in the Models list).
    let onStateChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle
            binaryRow
            statusRow
            if controller.discoveredGGUFs.isEmpty {
                emptyHint
            } else {
                ForEach(controller.discoveredGGUFs) { file in
                    ggufRow(file)
                }
            }
        }
        .onChange(of: controller.state) { _, new in
            // Ping upstream whenever we reach `running` so the Models list
            // gets an immediate refresh instead of waiting for the next
            // user-triggered rescan.
            if case .running = new { onStateChange() }
        }
    }

    // MARK: - Section title + rescan

    private var sectionTitle: some View {
        HStack {
            Text("local GGUFs (llama.cpp)")
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(AuroraGradient.linear(.full))
                .textCase(.uppercase)
            Spacer()
            Button {
                controller.rescanLocal()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                    Text("rescan disk")
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundStyle(Midnight.fog)
            }
            .buttonStyle(.plain)
            .help("Re-walk ~/models and ~/.cache/huggingface/hub for .gguf files")
        }
    }

    // MARK: - llama-server binary status

    @ViewBuilder
    private var binaryRow: some View {
        if let bin = controller.binaryURL {
            HStack(spacing: 8) {
                AuroraRing(size: 12, lineWidth: 1.5, state: .success)
                Text("llama-server")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Midnight.mist)
                Text(bin.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
        } else {
            HStack(spacing: 8) {
                AuroraRing(size: 12, lineWidth: 1.5, state: .failure)
                Text("llama-server not found — `brew install llama.cpp`")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
                Spacer()
            }
        }
    }

    // MARK: - Current server status

    @ViewBuilder
    private var statusRow: some View {
        switch controller.state {
        case .stopped:
            EmptyView()
        case .starting(let name):
            HStack(spacing: 8) {
                OmegaSpinner(size: 12)
                Text("starting · \(name) — polling /v1/models")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.mist)
                Spacer()
                Button(role: .destructive, action: controller.stop) {
                    Text("cancel")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Midnight.fog)
                }
                .buttonStyle(.plain)
            }
        case .running(let name):
            HStack(spacing: 8) {
                AuroraRing(size: 12, lineWidth: 1.5, state: .running)
                Text("running · \(name) · 127.0.0.1:8080")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.mist)
                Spacer()
                Button(role: .destructive, action: controller.stop) {
                    Text("stop")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Midnight.fog)
                }
                .buttonStyle(.plain)
            }
        case .crashed(let reason):
            HStack(spacing: 8) {
                AuroraRing(size: 12, lineWidth: 1.5, state: .failure)
                Text("crashed · \(reason)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
                    .lineLimit(2)
                Spacer()
            }
        }
    }

    private var emptyHint: some View {
        Text("No GGUF files found in ~/models or ~/.cache/huggingface/hub. Download one with `hf download ...`, then click rescan.")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Midnight.fog)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Per-file row

    private func ggufRow(_ file: GGUFFile) -> some View {
        HStack(spacing: 10) {
            // Leading dot: glowing when this file is the one currently served.
            AuroraRing(size: 12, lineWidth: 1.5,
                       state: isServedByMe(file) ? .running : .idle)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Midnight.mist)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(file.displayLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Midnight.fog)
                    if let size = file.sizeBytes {
                        Text("· \(formatBytes(size))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Midnight.fog)
                    }
                    if file.companionMmproj != nil {
                        Text("· +mmproj")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Midnight.fog)
                    }
                }
            }
            Spacer()
            startStopButton(for: file)
        }
        .padding(10)
        .background(Midnight.abyss)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func startStopButton(for file: GGUFFile) -> some View {
        let active = isServedByMe(file)
        return Button {
            if active {
                controller.stop()
            } else {
                controller.start(file)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: active ? "stop.circle" : "play.circle")
                    .font(.system(size: 11))
                Text(active ? "stop" : "start")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
            }
            .foregroundStyle(Midnight.mist)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Midnight.indigoDeep)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AuroraGradient.linear(.full), lineWidth: 0.8)
                    .opacity(active ? 0.85 : 0.55)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(controller.binaryURL == nil || isBusyExceptThis(file))
    }

    // MARK: - Helpers

    private func isServedByMe(_ file: GGUFFile) -> Bool {
        switch controller.state {
        case .starting(let name), .running(let name):
            return name == file.displayLabel
        default:
            return false
        }
    }

    private func isBusyExceptThis(_ file: GGUFFile) -> Bool {
        switch controller.state {
        case .starting(let name), .running(let name):
            return name != file.displayLabel
        default:
            return false
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.0f MB", mb)
    }
}
