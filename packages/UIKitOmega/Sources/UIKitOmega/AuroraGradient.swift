#if canImport(SwiftUI)
import SwiftUI

/// Aurora-fusion gradient — the one piece of chrome that appears on every surface.
///
/// `.full` is the rainbow fusion used in the Chat / Agents / Video tabs.
/// `.code` is the cooler sub-palette used only in the Code tab (cyan → teal →
/// indigo → violet).
public enum AuroraGradient {

    public enum Palette: Sendable {
        case full   // Chat, Agents, Video, default chrome
        case code   // Code tab only

        public var stops: [Gradient.Stop] {
            switch self {
            case .full:
                return [
                    .init(color: Color(red: 1.00, green: 0.231, blue: 0.420), location: 0.00), // #FF3B6B
                    .init(color: Color(red: 1.00, green: 0.541, blue: 0.239), location: 0.14), // #FF8A3D
                    .init(color: Color(red: 1.00, green: 0.824, blue: 0.239), location: 0.28), // #FFD23D
                    .init(color: Color(red: 0.302, green: 0.886, blue: 0.549), location: 0.42), // #4DE28C
                    .init(color: Color(red: 0.231, green: 0.776, blue: 1.00), location: 0.56),  // #3BC6FF
                    .init(color: Color(red: 0.478, green: 0.361, blue: 1.00), location: 0.70),  // #7A5CFF
                    .init(color: Color(red: 0.788, green: 0.294, blue: 1.00), location: 0.84),  // #C94BFF
                    .init(color: Color(red: 1.00, green: 0.231, blue: 0.420), location: 1.00)   // wrap
                ]
            case .code:
                return [
                    .init(color: Color(red: 0.231, green: 0.776, blue: 1.00), location: 0.00), // #3BC6FF
                    .init(color: Color(red: 0.302, green: 0.886, blue: 0.839), location: 0.33), // #4DE2D6
                    .init(color: Color(red: 0.478, green: 0.361, blue: 1.00), location: 0.66), // #7A5CFF
                    .init(color: Color(red: 0.788, green: 0.294, blue: 1.00), location: 1.00)  // #C94BFF
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
