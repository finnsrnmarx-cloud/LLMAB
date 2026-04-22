import SwiftUI
import UIKitOmega

/// Three-column app shell:
///   - Tab rail (left): Code (top-left, per spec), Chat, Agents, Video
///   - Active tab content (center, switching on selection)
///   - Title bar overlay carrying the animated ω mark
struct RootView: View {
    @State private var selection: TabKind = .default

    var body: some View {
        ZStack(alignment: .top) {
            Midnight.void.ignoresSafeArea()

            HStack(spacing: 0) {
                TabRail(selection: $selection)
                    .frame(width: 88)
                    .background(Midnight.midnight)

                Divider()
                    .overlay(AuroraGradient.linear(selection.palette).opacity(0.35))

                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Midnight.midnight)
            }

            TitleBar(palette: selection.palette)
                .frame(height: 36)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .code:     CodeTab()
        case .chat:     ChatTab()
        case .agents:   AgentsTab()
        case .video:    VideoTab()
        case .settings: SettingsTab()
        }
    }
}

// MARK: - Title bar

/// Slim titlebar overlay: drifting ω mark + product wordmark. The aurora
/// palette follows the active tab so the chrome shifts tone on tab switch.
private struct TitleBar: View {
    let palette: AuroraGradient.Palette

    var body: some View {
        HStack(spacing: 10) {
            OmegaMark(size: 22, animated: true, palette: palette)
            Text("llmab")
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(Midnight.mist)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(AuroraGradient.linear(palette))
                .frame(height: 1)
                .opacity(0.5)
        }
    }
}

// MARK: - Tab rail

private struct TabRail: View {
    @Binding var selection: TabKind

    /// Primary tabs (content creation / agents). Sit in the top group.
    private var primaryTabs: [TabKind] {
        TabKind.allCases.filter { $0 != .settings }
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 40)  // leave room for title bar
            ForEach(primaryTabs) { tab in
                RailButton(
                    kind: tab,
                    isSelected: selection == tab,
                    action: { selection = tab }
                )
            }
            Spacer()
            // Settings pinned to the bottom so the content tabs stay grouped.
            RailButton(
                kind: .settings,
                isSelected: selection == .settings,
                action: { selection = .settings }
            )
        }
        .padding(.vertical, 8)
    }
}

private struct RailButton: View {
    let kind: TabKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        isSelected
                        ? AnyShapeStyle(AuroraGradient.linear(kind.palette))
                        : AnyShapeStyle(Midnight.fog)
                    )
                Text(kind.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Midnight.mist : Midnight.fog)
            }
            .frame(width: 72, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Midnight.indigoDeep : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AuroraGradient.linear(kind.palette), lineWidth: isSelected ? 1 : 0)
                    .opacity(isSelected ? 0.6 : 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(kind.label))
    }
}
