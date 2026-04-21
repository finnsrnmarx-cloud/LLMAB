import Foundation

/// ANSI colour helpers. The CLI is visually a dim echo of the SwiftUI app —
/// the ω prefix, monospace feel, and aurora accent colours. We don't attempt
/// true-colour gradients in the terminal; we pick representative 24-bit stops.
enum Style {

    // Aurora stop samples (matches AuroraGradient.Palette.full).
    static let rose     = "\u{001B}[38;2;255;59;107m"    // #FF3B6B
    static let orange   = "\u{001B}[38;2;255;138;61m"    // #FF8A3D
    static let amber    = "\u{001B}[38;2;255;210;61m"    // #FFD23D
    static let green    = "\u{001B}[38;2;77;226;140m"    // #4DE28C
    static let cyan     = "\u{001B}[38;2;59;198;255m"    // #3BC6FF
    static let violet   = "\u{001B}[38;2;122;92;255m"    // #7A5CFF
    static let magenta  = "\u{001B}[38;2;201;75;255m"    // #C94BFF

    static let fog      = "\u{001B}[38;2;138;146;178m"   // #8A92B2
    static let mist     = "\u{001B}[38;2;199;204;224m"   // #C7CCE0

    static let bold     = "\u{001B}[1m"
    static let dim      = "\u{001B}[2m"
    static let reset    = "\u{001B}[0m"

    /// The lowercase ω mark, aurora-stroked.
    static let omega    = "\(violet)ω\(reset)"

    /// Prompt prefix used at the top of each subcommand.
    static func banner(_ subcommand: String) -> String {
        "\(omega) \(bold)\(mist)\(subcommand)\(reset)"
    }

    /// Colourise a name within a line.
    static func accent(_ text: String) -> String {
        "\(cyan)\(text)\(reset)"
    }

    static func muted(_ text: String) -> String {
        "\(fog)\(text)\(reset)"
    }

    static func error(_ text: String) -> String {
        "\(rose)\(text)\(reset)"
    }

    static func success(_ text: String) -> String {
        "\(green)\(text)\(reset)"
    }

    /// Count visible columns in a string, skipping ANSI CSI sequences
    /// (`ESC [ … m`). Used for column padding in the `models` table.
    static func visibleWidth(_ s: String) -> Int {
        var count = 0
        var inEscape = false
        let esc = Character(UnicodeScalar(0x1B))
        for char in s {
            if inEscape {
                if char == "m" { inEscape = false }
                continue
            }
            if char == esc {
                inEscape = true
                continue
            }
            count += 1
        }
        return count
    }

    /// Human-readable file size ("4.3 GB", "128 MB").
    static func bytes(_ n: Int64?) -> String {
        guard let n = n, n > 0 else { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(n)
        var idx = 0
        while value >= 1024, idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        return String(format: "%.1f %@", value, units[idx])
    }
}
