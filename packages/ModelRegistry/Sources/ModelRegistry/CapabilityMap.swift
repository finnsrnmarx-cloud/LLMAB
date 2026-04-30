import Foundation
import LLMCore

/// Static compatibility matrix for known model families. The Ollama adapter
/// gives us `ModelInfo` with `.textOnly` capabilities; `CapabilityMap.upgrade`
/// replaces that with the real matrix so the UI can feature-gate correctly.
///
/// New families are added here as a single entry. No other code changes.
public enum CapabilityMap {

    /// Resolve capabilities for a model. Looks up a small set of normalized
    /// identifiers from family/raw/display names, then falls back to the
    /// conservative runtime-provided default.
    public static func capabilities(for info: ModelInfo) -> ModelCapabilities {
        for key in candidateKeys(for: info) {
            if let exact = table[key] {
                return exact
            }
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
        let f = normalize(family)
        let v = variant.map(normalize)
        return v.map { "\(f):\($0)" } ?? f
    }

    private static func candidateKeys(for info: ModelInfo) -> [String] {
        var keys: [String] = [
            normalizedKey(family: info.family, variant: info.variant),
            normalizedKey(family: info.family, variant: nil),
            normalize(info.rawName),
            normalize(info.displayName),
            normalize(info.id)
        ]

        let searchable = keys.joined(separator: " ")
        for alias in aliases where searchable.contains(alias.match) {
            keys.append(alias.key)
        }

        return keys.uniqued()
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "·", with: "-")
    }

    private static let aliases: [(match: String, key: String)] = [
        ("deepseek-v4-flash", "deepseek-v4-flash"),
        ("deepseek-v4-pro", "deepseek-v4-pro"),
        ("deepseek-chat", "deepseek-chat"),
        ("deepseek-reasoner", "deepseek-reasoner"),
        ("qwen2.5-vl", "qwen-vl"),
        ("qwen2-vl", "qwen-vl"),
        ("qwen-2.5-vl", "qwen-vl"),
        ("qwen-3-vl", "qwen-vl"),
        ("qwen-vl", "qwen-vl"),
        ("minicpm-v", "minicpm-v"),
        ("minicpmv", "minicpm-v"),
        ("llava", "llava"),
        ("llama-3.2-vision", "llama-3.2-vision"),
        ("llama-3.2", "llama-3"),
        ("llama-3.1", "llama-3"),
        ("mistral", "mistral"),
        ("pixtral", "pixtral"),
        ("phi-4-multimodal", "phi-vision"),
        ("phi-3.5-vision", "phi-vision"),
        ("phi", "phi")
    ]

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
            tags: ["gemma-4", "edge", "audio-in", "image-in", "thinking"],
            videoProfile: .sampledFrames(maxFrameRate: 2, maxClipSeconds: 10)
        ),

        "gemma-4:e4b": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: true,  audioOut: false,
            videoIn: false, videoOut: false,
            toolUse: true,  thinking: true,
            contextTokens: 256_000,
            tags: ["gemma-4", "edge", "audio-in", "image-in", "thinking", "recommended"],
            videoProfile: .sampledFrames(maxFrameRate: 2, maxClipSeconds: 10)
        ),

        "gemma-4:26b": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: false, audioOut: false,
            videoIn: true,  videoOut: false,
            toolUse: true,  thinking: true,
            contextTokens: 256_000,
            tags: ["gemma-4", "moe", "video-in", "image-in", "thinking"],
            videoProfile: .sampledFrames(maxFrameRate: 1, maxClipSeconds: 60)
        ),

        "gemma-4:31b": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: false, audioOut: false,
            videoIn: true,  videoOut: false,
            toolUse: true,  thinking: true,
            contextTokens: 256_000,
            tags: ["gemma-4", "dense", "video-in", "image-in", "thinking"],
            videoProfile: .sampledFrames(maxFrameRate: 1, maxClipSeconds: 60)
        ),

        // Family-only fallback for unknown Gemma 4 variants (future tags).
        "gemma-4": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: false, audioOut: false,
            videoIn: false, videoOut: false,
            toolUse: true, thinking: true,
            contextTokens: 128_000,
            tags: ["gemma-4"],
            videoProfile: .sampledFrames(maxFrameRate: 2, maxClipSeconds: 10)
        ),

        // MARK: Gemma 3 (legacy)

        "gemma-3": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: false, audioOut: false,
            videoIn: false, videoOut: false,
            toolUse: false, thinking: false,
            contextTokens: 128_000,
            tags: ["gemma-3", "legacy"],
            videoProfile: .sampledFrames(maxFrameRate: 2, maxClipSeconds: 10)
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

        "llama-3.2-vision": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true,
            toolUse: true,
            contextTokens: 128_000,
            tags: ["llama-3", "vision", "image-in"],
            videoProfile: .sampledFrames(maxFrameRate: 2, maxClipSeconds: 10)
        ),

        "qwen-3": ModelCapabilities(
            textIn: true, textOut: true,
            toolUse: true, thinking: true,
            contextTokens: 128_000,
            tags: ["qwen-3", "thinking"]
        ),

        "qwen-vl": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true,
            toolUse: true, thinking: true,
            contextTokens: 128_000,
            tags: ["qwen", "vl", "image-in", "clip"],
            videoProfile: .sampledFrames(maxFrameRate: 4, maxClipSeconds: 20)
        ),

        "minicpm-v": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true,
            contextTokens: 64_000,
            tags: ["minicpm-v", "image-in", "clip"],
            videoProfile: .sampledFrames(maxFrameRate: 4, maxClipSeconds: 20)
        ),

        "llava": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true,
            contextTokens: 32_000,
            tags: ["llava", "image-in"],
            videoProfile: .sampledFrames(maxFrameRate: 2, maxClipSeconds: 10)
        ),

        "mistral": ModelCapabilities(
            textIn: true, textOut: true,
            toolUse: true,
            contextTokens: 128_000,
            tags: ["mistral"]
        ),

        "pixtral": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true,
            toolUse: true,
            contextTokens: 128_000,
            tags: ["mistral", "pixtral", "image-in"],
            videoProfile: .sampledFrames(maxFrameRate: 2, maxClipSeconds: 10)
        ),

        "phi": ModelCapabilities(
            textIn: true, textOut: true,
            contextTokens: 128_000,
            tags: ["phi"]
        ),

        "phi-vision": ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, audioIn: true,
            contextTokens: 128_000,
            tags: ["phi", "vision", "image-in", "audio-in"],
            videoProfile: .sampledFrames(maxFrameRate: 2, maxClipSeconds: 10)
        ),

        // MARK: DeepSeek cloud API (OpenAI-compatible, opt-in)

        "deepseek-v4-flash": ModelCapabilities(
            textIn: true, textOut: true,
            toolUse: true, thinking: true,
            contextTokens: 1_000_000,
            tags: ["deepseek", "cloud", "tool", "thinking"],
            videoProfile: VideoIngestionProfile.none,
            privacy: .cloudProvider
        ),

        "deepseek-v4-pro": ModelCapabilities(
            textIn: true, textOut: true,
            toolUse: true, thinking: true,
            contextTokens: 1_000_000,
            tags: ["deepseek", "cloud", "tool", "thinking", "pro"],
            videoProfile: VideoIngestionProfile.none,
            privacy: .cloudProvider
        ),

        "deepseek-chat": ModelCapabilities(
            textIn: true, textOut: true,
            toolUse: true,
            contextTokens: 1_000_000,
            tags: ["deepseek", "cloud", "compat", "deprecated-name"],
            videoProfile: VideoIngestionProfile.none,
            privacy: .cloudProvider
        ),

        "deepseek-reasoner": ModelCapabilities(
            textIn: true, textOut: true,
            toolUse: true, thinking: true,
            contextTokens: 1_000_000,
            tags: ["deepseek", "cloud", "thinking", "compat", "deprecated-name"],
            videoProfile: VideoIngestionProfile.none,
            privacy: .cloudProvider
        )
    ]
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
