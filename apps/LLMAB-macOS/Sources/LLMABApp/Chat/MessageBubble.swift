import SwiftUI
import LLMCore
import UIKitOmega

/// One row in the conversation. User turns sit right-aligned with an
/// indigo-deep background; assistant turns sit left-aligned with a slim
/// aurora-gradient stripe on the leading edge.
struct MessageBubble: View {
    let message: Message
    let isStreaming: Bool

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system, .tool:
            EmptyView()
        }
    }

    // MARK: - User

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.textContent)
                .font(.system(.body))
                .foregroundStyle(Midnight.mist)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Midnight.navy)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .textSelection(.enabled)
        }
    }

    // MARK: - Assistant

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(AuroraGradient.linear(.full, startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 6) {
                if message.textContent.isEmpty && isStreaming {
                    OmegaSpinner(size: 16)
                } else {
                    Text(message.textContent)
                        .font(.system(.body))
                        .foregroundStyle(Midnight.mist)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)

            Spacer(minLength: 0)
        }
    }
}
