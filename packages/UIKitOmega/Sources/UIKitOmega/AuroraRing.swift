#if canImport(SwiftUI)
import SwiftUI

/// Rotating halo rendered with the aurora angular gradient. Used for peripheral
/// in-progress indicators — runtime detection rows, tool-call side chips, the
/// live-capture overlay in the Video tab.
///
/// `state` lets the ring settle into a success / failure tint when an op
/// finishes, instead of just vanishing.
public struct AuroraRing: View {

    public enum RingState: Sendable {
        case idle
        case running
        case success
        case failure
    }

    public var size: CGFloat
    public var lineWidth: CGFloat
    public var state: RingState
    public var palette: AuroraGradient.Palette

    @State private var rotation: Double = 0

    public init(size: CGFloat = 22,
                lineWidth: CGFloat = 2.5,
                state: RingState = .running,
                palette: AuroraGradient.Palette = .full) {
        self.size = size
        self.lineWidth = lineWidth
        self.state = state
        self.palette = palette
    }

    public var body: some View {
        Circle()
            .strokeBorder(strokeStyle, lineWidth: lineWidth)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(state == .running ? rotation : 0))
            .onAppear {
                guard state == .running else { return }
                withAnimation(.linear(duration: UIKitOmega.spinDurationSeconds)
                                .repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
            .animation(.easeInOut(duration: 0.25), value: state)
            .accessibilityLabel(accessibilityText)
    }

    // MARK: - Style resolution

    private var strokeStyle: AnyShapeStyle {
        switch state {
        case .idle:
            return AnyShapeStyle(Midnight.fog.opacity(0.35))
        case .running:
            return AnyShapeStyle(AuroraGradient.angular(palette))
        case .success:
            return AnyShapeStyle(Color(red: 0.302, green: 0.886, blue: 0.549)) // #4DE28C
        case .failure:
            return AnyShapeStyle(Color(red: 1.00, green: 0.337, blue: 0.420)) // #FF5670
        }
    }

    private var accessibilityText: String {
        switch state {
        case .idle: "idle"
        case .running: "running"
        case .success: "finished"
        case .failure: "failed"
        }
    }
}

#Preview {
    ZStack {
        Midnight.midnight.ignoresSafeArea()
        HStack(spacing: 24) {
            AuroraRing(size: 40, state: .idle)
            AuroraRing(size: 40, state: .running)
            AuroraRing(size: 40, state: .success)
            AuroraRing(size: 40, state: .failure)
        }
    }
}
#endif
