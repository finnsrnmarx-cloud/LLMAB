import Foundation

/// Privacy boundary for a model. Local models keep inference on-device or
/// loopback-only; cloud providers may transmit prompts to a third-party API.
public enum ModelPrivacyBoundary: String, Sendable, Hashable, Codable {
    case localOnly
    case cloudProvider
}

/// How a model/runtime can ingest camera context. Even when a model has no
/// native video endpoint, it may still understand ordered image-frame clips.
public struct VideoIngestionProfile: Sendable, Hashable, Codable {
    public var snapshot: Bool
    public var sampledClip: Bool
    public var nativeVideo: Bool
    public var maxFrameRate: Double
    public var maxClipSeconds: Double

    public init(snapshot: Bool = false,
                sampledClip: Bool = false,
                nativeVideo: Bool = false,
                maxFrameRate: Double = 0,
                maxClipSeconds: Double = 0) {
        self.snapshot = snapshot
        self.sampledClip = sampledClip
        self.nativeVideo = nativeVideo
        self.maxFrameRate = maxFrameRate
        self.maxClipSeconds = maxClipSeconds
    }

    public static let none = VideoIngestionProfile()

    public static let snapshotOnly = VideoIngestionProfile(
        snapshot: true,
        sampledClip: false,
        nativeVideo: false,
        maxFrameRate: 1,
        maxClipSeconds: 0
    )

    public static func sampledFrames(maxFrameRate: Double = 2,
                                     maxClipSeconds: Double = 10) -> VideoIngestionProfile {
        VideoIngestionProfile(
            snapshot: true,
            sampledClip: true,
            nativeVideo: false,
            maxFrameRate: maxFrameRate,
            maxClipSeconds: maxClipSeconds
        )
    }

    public static func native(maxFrameRate: Double,
                              maxClipSeconds: Double) -> VideoIngestionProfile {
        VideoIngestionProfile(
            snapshot: true,
            sampledClip: true,
            nativeVideo: true,
            maxFrameRate: maxFrameRate,
            maxClipSeconds: maxClipSeconds
        )
    }
}

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

    /// Camera/video ingest policy used by the Video tab.
    public var videoProfile: VideoIngestionProfile

    /// Whether selecting this model can send user data off-device.
    public var privacy: ModelPrivacyBoundary

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
                tags: [String] = [],
                videoProfile: VideoIngestionProfile? = nil,
                privacy: ModelPrivacyBoundary = .localOnly) {
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
        if let videoProfile {
            self.videoProfile = videoProfile
        } else if videoIn {
            self.videoProfile = .sampledFrames(maxFrameRate: 1, maxClipSeconds: 60)
        } else if imageIn {
            self.videoProfile = .sampledFrames(maxFrameRate: 2, maxClipSeconds: 10)
        } else {
            self.videoProfile = .none
        }
        self.privacy = privacy
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
