#if canImport(SwiftUI)
import SwiftUI

/// Centralised font stack for ω. Instead of scattering `.system(.caption,
/// design: .monospaced).weight(.semibold)` across every view, the app calls
/// `Typography.meta` (or equivalent semantic names) so the typography
/// palette stays consistent and swappable.
///
/// **Current defaults** use Apple's SF system stack:
///   - UI body: SF Pro
///   - Headings: SF Pro Rounded (semibold)
///   - Code / logs / chips: SF Mono
///
/// **Swapping in a custom font.** Drop TTF or OTF files into a Resources/
/// Fonts/ directory inside the app target, register them via
/// `ATSApplicationFontsPath` in Info.plist, and set
/// `Typography.bundledFamilyName = "Inter"` (or whichever) early in app
/// startup. Every Typography style then resolves to that family, falling
/// back to SF if the custom font can't be loaded.
public enum Typography {

    /// Custom font family to use for UI / body / monospaced text. Nil uses
    /// Apple's system stack.
    public static var bundledFamilyName: String?

    /// Custom font family specifically for monospaced (code / logs).
    /// Fallback: bundledFamilyName, then SF Mono.
    public static var bundledMonoFamilyName: String?

    // MARK: - Semantic styles (what views should call)

    /// Primary headings — tab titles, dialog titles, onboarding slates.
    public static var title: Font { make(size: 20, weight: .semibold, design: .rounded) }

    /// Secondary headings — section labels like "Runtimes", "Models".
    public static var subtitle: Font { make(size: 13, weight: .semibold, design: .rounded) }

    /// Default body text — chat bubbles, tab content.
    public static var body: Font { make(size: 14, weight: .regular, design: .default) }

    /// Slightly smaller body — composer placeholder, subtitle strings.
    public static var bodySmall: Font { make(size: 12, weight: .regular, design: .default) }

    /// Meta / captions — subtitles on the rail, tooltip text, capability
    /// badges after a sentence. Semi-bold so it reads as "ui chrome".
    public static var meta: Font { make(size: 11, weight: .medium, design: .monospaced) }

    /// Meta at caption2 size — used on tiny chips, step numbers, etc.
    public static var micro: Font { make(size: 9, weight: .semibold, design: .monospaced) }

    /// Monospaced content — code blocks, logs, transcript output.
    public static var mono: Font { makeMono(size: 12, weight: .regular) }

    /// Larger monospaced — the CLIPrompt input, transcript assistant text.
    public static var monoLarge: Font { makeMono(size: 14, weight: .regular) }

    // MARK: - Builders

    private static func make(size: CGFloat, weight: Font.Weight, design: Font.Design) -> Font {
        if let family = bundledFamilyName,
           design != .monospaced,
           customFontExists(family) {
            return .custom(family, size: size).weight(weight)
        }
        if design == .monospaced { return makeMono(size: size, weight: weight) }
        return .system(size: size, weight: weight, design: design)
    }

    private static func makeMono(size: CGFloat, weight: Font.Weight) -> Font {
        if let family = bundledMonoFamilyName ?? bundledFamilyName,
           customFontExists(family) {
            return .custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    private static func customFontExists(_ family: String) -> Bool {
        #if canImport(AppKit)
        return NSFontManager.shared.availableFontFamilies.contains(family)
        #elseif canImport(UIKit)
        return UIFont.familyNames.contains(family)
        #else
        return false
        #endif
    }
}

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
#endif
