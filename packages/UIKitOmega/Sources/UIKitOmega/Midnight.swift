#if canImport(SwiftUI)
import SwiftUI

/// Near-black base palette. Mirrors `assets/brand/midnight-tokens.json`.
public enum Midnight {
    public static let void        = Color(red: 0.020, green: 0.027, blue: 0.071)  // #050712
    public static let midnight    = Color(red: 0.039, green: 0.043, blue: 0.078)  // #0A0B14
    public static let abyss       = Color(red: 0.063, green: 0.075, blue: 0.165)  // #10132A
    public static let indigoDeep  = Color(red: 0.078, green: 0.094, blue: 0.157)  // #141828
    public static let navy        = Color(red: 0.110, green: 0.137, blue: 0.251)  // #1C2340
    public static let fog         = Color(red: 0.541, green: 0.573, blue: 0.698)  // #8A92B2
    public static let mist        = Color(red: 0.780, green: 0.800, blue: 0.878)  // #C7CCE0
    public static let whiteOmega  = Color(red: 0.961, green: 0.965, blue: 0.980)  // #F5F6FA
}
#endif
