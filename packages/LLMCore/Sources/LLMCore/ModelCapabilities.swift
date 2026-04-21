import Foundation

/// What a given model can actually do. The UI reads this to gate tabs and
/// sub-modes; feature badges in Settings render from the same struct.
///
/// Separate in/out flags so we can represent, for example, a vision model that
/// can *accept* images but cannot *emit* them (true for every Gemma 4 variant).
public struct ModelCapabilities: Sendable, Hashable, Codable {

    public var textIn: Bool
    public var textOut: Bool
    public var imageIn: Bool
    public var imageOut: Bool
    public var audioIn: Bool
    public var audioOut: Bool
    public var videoIn: Bool
    public var videoOut: Bool

    /// Native function-calling / tool-use support.
    public var toolUse: Bool

    /// Exposes a configurable "thinking" mode (Gemma 4 term).
    public var thinking: Bool

    /// Maximum context window in tokens (e.g. 256_000 for Gemma 4).
    public var contextTokens: Int

    /// Free-form comma-separated tags surfaced in the capability-badge UI.
    public var tags: [String]

    public init(textIn: Bool = true,
                textOut: Bool = true,
                imageIn: Bool = false,
                imageOut: Bool = false,
                audioIn: Bool = false,
                audioOut: Bool = false,
                videoIn: Bool = false,
                videoOut: Bool = false,
                toolUse: Bool = false,
                thinking: Bool = false,
                contextTokens: Int = 8_192,
                tags: [String] = []) {
        self.textIn = textIn
        self.textOut = textOut
        self.imageIn = imageIn
        self.imageOut = imageOut
        self.audioIn = audioIn
        self.audioOut = audioOut
        self.videoIn = videoIn
        self.videoOut = videoOut
        self.toolUse = toolUse
        self.thinking = thinking
        self.contextTokens = contextTokens
        self.tags = tags
    }

    /// Predicate used throughout the UI: does this model support a given
    /// modality on input?
    public func accepts(_ m: Modality) -> Bool {
        switch m {
        case .text: textIn
        case .image: imageIn
        case .audio: audioIn
        case .video: videoIn
        }
    }

    public func emits(_ m: Modality) -> Bool {
        switch m {
        case .text: textOut
        case .image: imageOut
        case .audio: audioOut
        case .video: videoOut
        }
    }

    /// Pure text-only LLM, no tool-use. Conservative default.
    public static let textOnly = ModelCapabilities()
}
