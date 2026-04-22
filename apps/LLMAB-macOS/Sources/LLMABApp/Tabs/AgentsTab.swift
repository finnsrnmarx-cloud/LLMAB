import SwiftUI
import AgentKit
import UIKitOmega

/// Agents tab — tool-use loop with consent-gated shell. Outer shell reads
/// the long-lived view-model from AppStore and hands it to an inner
/// @ObservedObject subview so SwiftUI actually tracks VM changes. (If we
/// tried to observe `store.agentsVM` from the outer view directly SwiftUI
/// wouldn't re-render on `vm.turns`/`vm.isRunning` updates — those are
/// nested @Published and don't propagate through AppStore's
/// objectWillChange.)
struct AgentsTab: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        AgentsTabContent(vm: store.agentsVM)
    }
}

private struct AgentsTabContent: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var vm: AgentsTabViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("Agents",
                      subtitle: subtitle,
                      palette: .full,
                      showSpinner: vm.isRunning)

            toolBar
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            transcript

            Divider().overlay(AuroraGradient.linear(.full).opacity(0.25))

            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // vm is bound in AppStore.init.
        .sheet(item: $vm.pendingConsent) { pending in
            ConsentSheet(pending: pending) { allow in
                vm.resolveConsent(pending.id, allow: allow)
            }
        }
    }

    // MARK: - Bars

    private var toolBar: some View {
        HStack(spacing: 10) {
            toolChip("read_file")
            toolChip("write_file")
            toolChip("list_dir")
            toolChip("run_shell", requiresConsent: true)
            Toggle(isOn: $vm.enableWebSearch) {
                Text("web_search")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            }
            .toggleStyle(.switch)
            Spacer()
            Button(action: vm.reset) {
                Text("reset")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            }
            .buttonStyle(.plain)
            .disabled(vm.turns.isEmpty)
        }
    }

    private func toolChip(_ name: String, requiresConsent: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: requiresConsent ? "lock.shield" : "wrench.and.screwdriver")
                .font(.system(size: 9))
            Text(name)
                .font(.system(.caption2, design: .monospaced))
        }
        .foregroundStyle(Midnight.fog)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Midnight.abyss)
        .overlay(
            Capsule().stroke(AuroraGradient.linear(.full), lineWidth: 0.5).opacity(0.3)
        )
        .clipShape(Capsule())
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if vm.turns.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.turns) { turn in
                            AgentTranscriptRow(turn: turn).id(turn.id)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: vm.turns.count) { _, _ in
                if let last = vm.turns.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                OmegaMark(size: 18, animated: true)
                Text("give ω a task")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Midnight.mist)
            }
            Text("""
            Examples: "summarise every .md file in ~/code/repo", "find the \
            biggest file in Downloads", "run swift test in the workspace". \
            Every shell call pauses for your approval.
            """)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Midnight.fog)
        }
        .padding(.top, 36)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("ask the agent…", text: $vm.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .default))
                .foregroundStyle(Midnight.mist)
                .lineLimit(1...6)
                .onSubmit { vm.send() }
            if vm.isRunning {
                Button(action: vm.cancel) {
                    OmegaSpinner(size: 22)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: vm.send) {
                    OmegaMark(size: 22, animated: !vm.input.isEmpty)
                        .opacity(vm.input.isEmpty ? 0.35 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(vm.input.isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Midnight.indigoDeep)
        .overlay(alignment: .top) {
            Rectangle().fill(AuroraGradient.linear(.full)).frame(height: 1).opacity(0.35)
        }
    }

    private var subtitle: String {
        "tool-use · aurora-full" + (vm.enableWebSearch ? " · web on" : "")
    }
}

// MARK: - Consent sheet

private struct ConsentSheet: View {
    let pending: AgentsTabViewModel.PendingConsent
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                AuroraRing(size: 18, lineWidth: 2, state: .running)
                Text("approve \(pending.toolId)?")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Midnight.mist)
            }
            ScrollView {
                Text(prettyJSON(pending.argumentsJSON))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Midnight.mist)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 200)
            .background(Midnight.abyss)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Button("deny") { decide(false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("approve") { decide(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Midnight.midnight)
    }

    private func prettyJSON(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: pretty, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? "<binary>"
        }
        return s
    }
}
