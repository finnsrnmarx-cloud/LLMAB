import SwiftUI
import LLMCore
import UIKitOmega
import UniformTypeIdentifiers

/// Scrolling message list + composer. The view model is injected from
/// ChatTab so that both ChatConversationView and DictateView share a single
/// conversation and send pipeline.
struct ChatConversationView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var vm: ChatViewModel

    init(chat: ChatViewModel) { self._vm = ObservedObject(wrappedValue: chat) }

    var body: some View {
        VStack(spacing: 0) {
            modelHeader
            messageList
            Divider().overlay(AuroraGradient.linear(.full).opacity(0.25))
            composer
        }
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

    @State private var isPickingImage: Bool = false

    private var composer: some View {
        VStack(spacing: 8) {
            if !vm.pendingAttachments.isEmpty {
                attachmentStrip
            }
            HStack(alignment: .bottom, spacing: 10) {
                attachButton
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
                        OmegaMark(size: 22, animated: !vm.input.isEmpty || !vm.pendingAttachments.isEmpty)
                            .opacity(isSendDisabled ? 0.35 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSendDisabled)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
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
        .fileImporter(
            isPresented: $isPickingImage,
            allowedContentTypes: [.png, .jpeg, .heic, .gif, .webP, .tiff],
            allowsMultipleSelection: true
        ) { result in
            handlePickResult(result)
        }
    }

    private var attachButton: some View {
        Button {
            isPickingImage = true
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AuroraGradient.linear(.full))
        }
        .buttonStyle(.plain)
        .disabled(!canAttachImages)
        .help(canAttachImages ? "attach image(s)" : "selected model does not accept images")
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.pendingAttachments) { a in
                    AttachmentChip(attachment: a) {
                        vm.removeAttachment(a.id)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var isSendDisabled: Bool {
        (vm.input.isEmpty && vm.pendingAttachments.isEmpty) || store.selectedModelId == nil
    }

    private var canAttachImages: Bool {
        guard let id = store.selectedModelId,
              let info = store.snapshot?.models.first(where: { $0.id == id }) else {
            return false
        }
        return info.capabilities.imageIn
    }

    private func handlePickResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        Task { @MainActor in
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { continue }
                let mime = mimeType(for: url)
                await vm.attachImage(
                    data: data,
                    mimeType: mime,
                    filename: url.lastPathComponent
                )
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "heic":         return "image/heic"
        case "gif":          return "image/gif"
        case "webp":         return "image/webp"
        case "tiff", "tif":  return "image/tiff"
        default:             return "image/png"
        }
    }
}

// MARK: - AttachmentChip

private struct AttachmentChip: View {
    let attachment: ImageAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 11))
                .foregroundStyle(AuroraGradient.linear(.full))
            Text(attachment.shortLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Midnight.mist)
                .lineLimit(1)
                .frame(maxWidth: 180)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Midnight.fog)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Midnight.navy)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AuroraGradient.linear(.full), lineWidth: 0.8)
                .opacity(0.5)
        )
    }
}
