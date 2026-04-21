import Foundation

/// Namespace + brand constants for the ω visual system.
///
/// The SwiftUI atoms (`OmegaMark`, `OmegaSpinner`, `AuroraRing`, `CLIPrompt`,
/// `AuroraGradient`, `Midnight`) live in sibling files, all gated behind
/// `#if canImport(SwiftUI)` so `swift build` on non-Apple hosts still succeeds.
public enum UIKitOmega {
    /// The product mark. Lowercase. Never a star.
    public static let mark: String = "ω"

    /// Default rotation duration for active-state indicators.
    public static let spinDurationSeconds: Double = 2.0

    /// Default hue-shift duration for the aurora gradient.
    public static let auroraShiftSeconds: Double = 8.0

    /// Bundle identifier prefix used by brand-owned Core Data / UserDefaults keys.
    public static let bundlePrefix: String = "org.llmab.omega"
}
