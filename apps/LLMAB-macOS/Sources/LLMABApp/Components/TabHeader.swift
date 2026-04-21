import SwiftUI
import UIKitOmega

/// Shared tab-header: big gradient title + subtitle. Used by every tab.
struct TabHeader: View {
    let title: String
    let subtitle: String
    let palette: AuroraGradient.Palette
    let showSpinner: Bool

    init(_ title: String,
         subtitle: String = "",
         palette: AuroraGradient.Palette = .full,
         showSpinner: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.palette = palette
        self.showSpinner = showSpinner
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(AuroraGradient.linear(palette))
            if showSpinner {
                OmegaSpinner(size: 20, palette: palette)
            }
            Spacer()
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 44)
        .padding(.bottom, 8)
    }
}

/// Placeholder card used by each tab until its real content ships in later
/// chunks. The card carries a rotating AuroraRing so the tab feels "alive"
/// even in its stub state.
struct PlaceholderCard: View {
    let title: String
    let message: String
    let palette: AuroraGradient.Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AuroraRing(size: 18, lineWidth: 2, state: .running, palette: palette)
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Midnight.mist)
            }
            Text(message)
                .font(.system(.body))
                .foregroundStyle(Midnight.fog)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Midnight.abyss)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AuroraGradient.linear(palette), lineWidth: 1)
                .opacity(0.35)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 24)
    }
}
