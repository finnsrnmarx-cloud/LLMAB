#if canImport(SwiftUI)
import SwiftUI

/// The lowercase ω mark rendered in the aurora gradient.
///
/// - `animated: true` slowly rotates the gradient angle so the stroke hue drifts
///   even when the app is idle. This is the titlebar treatment.
/// - `animated: false` renders a static sweep. Used for menu-bar glyphs and
///   non-interactive surfaces.
public struct OmegaMark: View {

    public var size: CGFloat
    public var animated: Bool
    public var palette: AuroraGradient.Palette

    @State private var phase: Double = 0

    public init(size: CGFloat = 28,
                animated: Bool = true,
                palette: AuroraGradient.Palette = .full) {
        self.size = size
        self.animated = animated
        self.palette = palette
    }

    public var body: some View {
        Text(UIKitOmega.mark)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(
                AuroraGradient.angular(
                    palette,
                    startAngle: .degrees(phase),
                    endAngle: .degrees(phase + 360)
                )
            )
            .onAppear {
                guard animated else { return }
                withAnimation(.linear(duration: UIKitOmega.auroraShiftSeconds)
                                .repeatForever(autoreverses: false)) {
                    phase = 360
                }
            }
            .accessibilityLabel("omega")
    }
}
#endif
