import SwiftUI
import LLMCore
import UIKitOmega

/// Scrolling message list + composer. Used by ChatTab when Mode == .chat.
struct ChatConversationView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var vm = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            modelHeader
            messageList
            Divider().overlay(AuroraGradient.linear(.full).opacity(0.25))
            composer
        }
        .onAppear { vm.bind(to: store) }
    }

    // MARK: - Model header strip

    private var modelHeader: some View {
        HStack(spacing: 8) {
            if let snap = store.snapshot,
               let id = store.selectedModelId,
               let info = snap.models.first(where: { $0.id == id }) {
                OmegaMark(size: 14, animated: true)
                Text(info.displayName)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Midnight.mist)
                capabilityPill("256K", active: true)
                if info.capabilities.thinking {
                    capabilityPill("think", active: true)
                }
                if info.capabilities.toolUse {
                    capabilityPill("tools", active: true)
                }
            } else {
                Text(store.isScanning ? "scanning runtimes…" : "no model selected")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
                if store.isScanning {
                    AuroraRing(size: 14, lineWidth: 1.5, state: .running)
                }
            }
            Spacer()
            Button {
                vm.newConversation()
            } label: {
                Text("new")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            }
            .buttonStyle(.plain)
            .disabled(vm.turns.isEmpty && !vm.isStreaming)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Midnight.abyss.opacity(0.5))
    }

    private func capabilityPill(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced).weight(.semibold))
            .foregroundStyle(active ? Midnight.mist : Midnight.fog)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Midnight.navy)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AuroraGradient.linear(.full), lineWidth: active ? 0.8 : 0)
                    .opacity(active ? 0.6 : 0)
            )
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if vm.turns.isEmpty {
                        emptyState
                            .padding(.top, 48)
                    } else {
                        ForEach(vm.turns) { turn in
                            MessageBubble(
                                message: turn,
                                isStreaming: vm.isStreaming && turn.id == vm.turns.last?.id
                            )
                            .id(turn.id)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
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
                Text("ask anything")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Midnight.mist)
            }
            Text("Replies stream from your local model. Nothing leaves this Mac.")
                .font(.system(.body))
                .foregroundStyle(Midnight.fog)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("message…", text: $vm.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .default))
                .foregroundStyle(Midnight.mist)
                .lineLimit(1...6)
                .onSubmit { vm.send() }

            if vm.isStreaming {
                Button(action: vm.cancel) {
                    OmegaSpinner(size: 22)
                }
                .buttonStyle(.plain)
                .help("cancel streaming")
            } else {
                Button(action: vm.send) {
                    OmegaMark(size: 22, animated: !vm.input.isEmpty)
                        .opacity(vm.input.isEmpty ? 0.35 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(vm.input.isEmpty || store.selectedModelId == nil)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Midnight.indigoDeep)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AuroraGradient.linear(.full))
                .frame(height: 1)
                .opacity(0.35)
        }
    }
}
