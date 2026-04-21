import Foundation
import LLMCore

/// Static compatibility matrix for known model families. The Ollama adapter
/// gives us `ModelInfo` with `.textOnly` capabilities; `CapabilityMap.upgrade`
/// replaces that with the real matrix so the UI can feature-gate correctly.
///
/// New families are added here as a single entry. No other code changes.
public enum CapabilityMap {

    /// Resolve capabilities for a model. Looks up the family + variant in the
    /// table; falls back to the conservative `.textOnly` default.
    public static func capabilities(for info: ModelInfo) -> ModelCapabilities {
        let key = normalizedKey(family: info.family, variant: info.variant)

        if let exact = table[key] {
            return exact
        }

        // Try family-only (e.g. "gemma-4" without variant).
        let familyKey = normalizedKey(family: info.family, variant: nil)
        if let familyDefault = table[familyKey] {
            return familyDefault
        }

        // Unknown family: keep conservative default but let the runtime's
        // own hint ride through.
        return info.capabilities
    }

    /// Returns a new `ModelInfo` with `.capabilities` overwritten from the map.
    public static func upgrade(_ info: ModelInfo) -> ModelInfo {
        var copy = info
        copy.capabilities = capabilities(for: info)
        return copy
    }

    /// All known families, for docs / settings UI enumeration.
    public static var allKnownKeys: [String] {
        Array(table.keys).sorted()
    }

    // MARK: - Table

    private static func normalizedKey(family: String, variant: String?) -> String {
        let f = family.lowercased().replacingOccurrences(of: "_", with: "-")
        let v = variant?.lowercased()
        return v.map { "\(f):\($0)" } ?? f
    }

    /// Source of truth: the `docs/GEMMA4-COMPATIBILITY.md` matrix plus a few
    /// non-Gemma entries we already know we'll meet.
    private static let table: [String: ModelCapabilities] = [

        // MARK: Gemma 4 (April 2026)

        "gemma-4:e2b": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: true,  audioOut: false,
            videoIn: false, videoOut: false,
            toolUse: true,  thinking: true,
            contextTokens: 256_000,
            tags: ["gemma-4", "edge", "audio-in", "image-in", "thinking"]
        ),

        "gemma-4:e4b": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: true,  audioOut: false,
            videoIn: false, videoOut: false,
            toolUse: true,  thinking: true,
            contextTokens: 256_000,
            tags: ["gemma-4", "edge", "audio-in", "image-in", "thinking", "recommended"]
        ),

        "gemma-4:26b": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: false, audioOut: false,
            videoIn: true,  videoOut: false,
            toolUse: true,  thinking: true,
            contextTokens: 256_000,
            tags: ["gemma-4", "moe", "video-in", "image-in", "thinking"]
        ),

        "gemma-4:31b": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: false, audioOut: false,
            videoIn: true,  videoOut: false,
            toolUse: true,  thinking: true,
            contextTokens: 256_000,
            tags: ["gemma-4", "dense", "video-in", "image-in", "thinking"]
        ),

        // Family-only fallback for unknown Gemma 4 variants (future tags).
        "gemma-4": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: false, audioOut: false,
            videoIn: false, videoOut: false,
            toolUse: true, thinking: true,
            contextTokens: 128_000,
            tags: ["gemma-4"]
        ),

        // MARK: Gemma 3 (legacy)

        "gemma-3": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: false, audioOut: false,
            videoIn: false, videoOut: false,
            toolUse: false, thinking: false,
            contextTokens: 128_000,
            tags: ["gemma-3", "legacy"]
        ),

        // MARK: Diffusion (optional Create-image sub-mode)

        "flux": ModelCapabilities(
            textIn: true, textOut: false,
            imageIn: false, imageOut: true,
            contextTokens: 512,
            tags: ["diffusion", "image-gen"]
        ),

        "sdxl": ModelCapabilities(
            textIn: true, textOut: false,
            imageIn: false, imageOut: true,
            contextTokens: 512,
            tags: ["diffusion", "image-gen"]
        ),

        "stable-diffusion": ModelCapabilities(
            textIn: true, textOut: false,
            imageIn: false, imageOut: true,
            contextTokens: 512,
            tags: ["diffusion", "image-gen"]
        ),

        // MARK: Non-Gemma LLMs we'll commonly meet

        "llama-3": ModelCapabilities(
            textIn: true, textOut: true,
            toolUse: true,
            contextTokens: 128_000,
            tags: ["llama-3"]
        ),

        "qwen-3": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true,
            toolUse: true, thinking: true,
            contextTokens: 128_000,
            tags: ["qwen-3", "image-in"]
        )
    ]
}
