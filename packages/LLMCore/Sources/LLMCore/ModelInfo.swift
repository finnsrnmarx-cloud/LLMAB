import Foundation

/// A single runnable model, as discovered by a runtime adapter.
public struct ModelInfo: Sendable, Hashable, Codable, Identifiable {

    /// Fully qualified identifier, e.g. `"ollama:gemma-4:e4b"` or
    /// `"mlx:mlx-community/gemma-4-e4b-4bit"`. Used as the primary key.
    public var id: String

    /// Raw name from the runtime (`gemma-4:e4b`). Prefer `displayName` for UI.
    public var rawName: String

    /// Human-readable label ("Gemma 4 · E4B").
    public var displayName: String

    /// Identifier of the owning runtime: "ollama", "mlx", "llamacpp".
    public var runtimeId: String

    /// Family / architecture hint used by the capability-inference heuristics.
    /// Examples: "gemma-4", "gemma-4-e", "llama-3", "flux", "sdxl".
    public var family: String

    /// Specific variant name within the family ("e2b", "e4b", "26b", "31b").
    public var variant: String?

    /// On-disk size in bytes if reported, otherwise nil.
    public var sizeBytes: Int64?

    /// Whether the runtime reports the model as currently loaded in memory.
    public var isLoaded: Bool

    /// Capabilities as resolved by the `ModelRegistry`. Adapters may leave this
    /// at `.textOnly` and let `ModelRegistry` upgrade it based on `family`.
    public var capabilities: ModelCapabilities

    public init(id: String,
                rawName: String,
                displayName: String,
                runtimeId: String,
                family: String,
                variant: String? = nil,
                sizeBytes: Int64? = nil,
                isLoaded: Bool = false,
                capabilities: ModelCapabilities = .textOnly) {
        self.id = id
        self.rawName = rawName
        self.displayName = displayName
        self.runtimeId = runtimeId
        self.family = family
        self.variant = variant
        self.sizeBytes = sizeBytes
        self.isLoaded = isLoaded
        self.capabilities = capabilities
    }
}
