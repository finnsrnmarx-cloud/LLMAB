import Foundation
import LLMCore

/// Namespace for on-device media services used by the macOS app:
/// ``DictationService`` (Apple Speech framework) for speech-to-text and
/// ``TTSService`` (AVSpeechSynthesizer) for text-to-speech.
///
/// Everything here is on-device, offline, and free — no third-party AI, which
/// keeps us firmly under Apple's guideline 5.1.2(i) exemption (see
/// `docs/APP-STORE.md`).
public enum MediaKit {
    public static let id = "media-kit"
}

public enum MediaKitError: Error, Sendable, CustomStringConvertible {
    case micPermissionDenied
    case speechPermissionDenied
    case recognizerUnavailable
    case audioEngineFailure(String)
    case noAuthorization

    public var description: String {
        switch self {
        case .micPermissionDenied: return "microphone permission denied"
        case .speechPermissionDenied: return "speech-recognition permission denied"
        case .recognizerUnavailable: return "speech recognizer not available on this device"
        case .audioEngineFailure(let s): return "audio engine error: \(s)"
        case .noAuthorization: return "permission must be requested first"
        }
    }
}
