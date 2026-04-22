#if canImport(SwiftUI)
import SwiftUI

/// Aurora-fusion gradient — the one piece of chrome that appears on every surface.
///
/// The new palette is a **Google-fade**: blue → green → yellow → red, extended
/// with a warm pink + soft purple pair. All stops are desaturated from the
/// original neon rainbow so chrome reads as "glow" rather than "parade".
///
/// - `.full` — every tab's default chrome (Chat / Agents / Video / Settings)
/// - `.code` — Code tab only (blue → teal → green → purple, skipping the warms)
public enum AuroraGradient {

    public enum Palette: Sendable {
        case full   // Chat, Agents, Video, Settings, default chrome
        case code   // Code tab only

        public var stops: [Gradient.Stop] {
            switch self {
            case .full:
                return [
                    // Blue  #5B8FD9
                    .init(color: Color(red: 0.357, green: 0.561, blue: 0.851), location: 0.00),
                    // Green #5FB074
                    .init(color: Color(red: 0.373, green: 0.690, blue: 0.455), location: 0.18),
                    // Yellow #E8C470 (warm, muted)
                    .init(color: Color(red: 0.910, green: 0.769, blue: 0.439), location: 0.36),
                    // Red   #D86A6A (soft coral)
                    .init(color: Color(red: 0.847, green: 0.416, blue: 0.416), location: 0.54),
                    // Pink  #D48BB8 (dusty)
                    .init(color: Color(red: 0.831, green: 0.545, blue: 0.722), location: 0.72),
                    // Purple #9B7BC7 (lavender)
                    .init(color: Color(red: 0.608, green: 0.482, blue: 0.780), location: 0.88),
                    // Loop back to blue for angular sweeps
                    .init(color: Color(red: 0.357, green: 0.561, blue: 0.851), location: 1.00)
                ]
            case .code:
                return [
                    // Blue  #5B8FD9
                    .init(color: Color(red: 0.357, green: 0.561, blue: 0.851), location: 0.00),
                    // Teal  #68B8B0
                    .init(color: Color(red: 0.408, green: 0.722, blue: 0.690), location: 0.33),
                    // Green #5FB074
                    .init(color: Color(red: 0.373, green: 0.690, blue: 0.455), location: 0.66),
                    // Purple #9B7BC7
                    .init(color: Color(red: 0.608, green: 0.482, blue: 0.780), location: 1.00)
                ]
            }
        }

        public var gradient: Gradient { Gradient(stops: stops) }
    }

    /// Linear sweep, used for strokes and underlines.
    public static func linear(_ palette: Palette = .full,
                              startPoint: UnitPoint = .topLeading,
                              endPoint: UnitPoint = .bottomTrailing) -> LinearGradient {
        LinearGradient(gradient: palette.gradient, startPoint: startPoint, endPoint: endPoint)
    }

    /// Angular sweep, used for rotating rings and spinner strokes.
    public static func angular(_ palette: Palette = .full,
                               center: UnitPoint = .center,
                               startAngle: Angle = .degrees(0),
                               endAngle: Angle = .degrees(360)) -> AngularGradient {
        AngularGradient(gradient: palette.gradient,
                        center: center,
                        startAngle: startAngle,
                        endAngle: endAngle)
    }

    /// Soft radial halo, used behind the ω mark on icon surfaces.
    public static func radial(_ palette: Palette = .full,
                              center: UnitPoint = .center,
                              startRadius: CGFloat = 2,
                              endRadius: CGFloat = 200) -> RadialGradient {
        RadialGradient(gradient: palette.gradient,
                       center: center,
                       startRadius: startRadius,
                       endRadius: endRadius)
    }
}
#endif
