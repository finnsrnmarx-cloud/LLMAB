#if canImport(SwiftUI)
import SwiftUI

/// Rotating ω. Every foreground in-progress op in the app uses this instead of
/// the system spinner — streaming tokens, dictation, pull progress, tool-use
/// step, etc.
///
/// The ω itself spins on its own axis; the aurora stroke drifts at a slower
/// rate so the mark doesn't feel mechanical.
public struct OmegaSpinner: View {

    public var size: CGFloat
    public var palette: AuroraGradient.Palette

    @State private var rotation: Double = 0
    @State private var hue: Double = 0

    public init(size: CGFloat = 24, palette: AuroraGradient.Palette = .full) {
        self.size = size
        self.palette = palette
    }

    public var body: some View {
        Text(UIKitOmega.mark)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(
                AuroraGradient.angular(
                    palette,
                    startAngle: .degrees(hue),
                    endAngle: .degrees(hue + 360)
                )
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: UIKitOmega.spinDurationSeconds)
                                .repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                withAnimation(.linear(duration: UIKitOmega.auroraShiftSeconds)
                                .repeatForever(autoreverses: false)) {
                    hue = 360
                }
            }
            .accessibilityLabel("working")
    }
}
#endif
