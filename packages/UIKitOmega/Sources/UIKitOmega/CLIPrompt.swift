#if canImport(SwiftUI)
import SwiftUI

/// The monospace ω-prefixed input row used at the bottom of the Code tab and
/// replicated visually in the `llmab` CLI binary's first line of output.
///
/// The prefix is always a static (non-spinning) aurora-stroked ω so the user
/// knows where input begins; active state is shown to the right of the field.
public struct CLIPrompt: View {

    @Binding public var text: String
    public var isWorking: Bool
    public var placeholder: String
    public var onSubmit: () -> Void

    public init(text: Binding<String>,
                isWorking: Bool = false,
                placeholder: String = "ask, edit, or run",
                onSubmit: @escaping () -> Void) {
        self._text = text
        self.isWorking = isWorking
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 10) {
            // ω prefix — stroked in the code-tab sub-palette so it visually
            // distinguishes from the Chat tab's full-spectrum ω.
            Text(UIKitOmega.mark)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(AuroraGradient.linear(.code))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Midnight.mist)
                .onSubmit(onSubmit)

            if isWorking {
                OmegaSpinner(size: 18, palette: .code)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Midnight.indigoDeep)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AuroraGradient.linear(.code), lineWidth: 1)
                .opacity(0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    struct Demo: View {
        @State var text = ""
        var body: some View {
            ZStack {
                Midnight.midnight.ignoresSafeArea()
                CLIPrompt(text: $text, isWorking: true) {}
                    .padding(24)
            }
        }
    }
    return Demo()
}
#endif
