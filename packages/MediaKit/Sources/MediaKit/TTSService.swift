#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// System text-to-speech wrapper. Uses AVSpeechSynthesizer — fully on-device,
/// free, offline. A future opt-in upgrade is Kokoro-TTS or Parakeet via MLX.
///
/// **Voice selection.** When the caller passes `voice: nil`, TTSService picks
/// the best-sounding **British English** voice installed on the system, in
/// this priority order:
///   1. Premium / Enhanced Siri en-GB voices (several on Apple Silicon once
///      the user has downloaded them via Settings → Accessibility →
///      Spoken Content → System Voice → English (UK))
///   2. Any other premium/enhanced en-GB voice (Daniel Premium, Serena, …)
///   3. Any en-GB voice at default quality
///   4. The Locale.current fallback — same behaviour as before.
///
/// **Pitch & rate.** `speak` tunes rate+pitch to ω's "calm, measured" voice
/// personality — slightly slower than default, slightly lower pitch. Callers
/// can override either per-utterance.
///
/// Not `@MainActor` so `StateObject`'s autoclosure initialiser can construct
/// an instance from wherever SwiftUI chooses; delegate callbacks hop to the
/// main actor before mutating `isSpeaking`.
public final class TTSService: NSObject, ObservableObject {

    @Published public private(set) var isSpeaking: Bool = false

    #if canImport(AVFoundation)
    private let synth = AVSpeechSynthesizer()
    #endif

    public override init() {
        super.init()
        #if canImport(AVFoundation)
        synth.delegate = self
        #endif
    }

    /// Speak `text`. If `voice` is nil, the best available British voice is
    /// used; see `defaultVoice()`. `rate` and `pitch` default to ω's
    /// personality (`0.48` and `0.95`) — slightly slower and slightly lower
    /// than AVSpeechSynthesizer's default.
    public func speak(_ text: String,
                      voice: String? = nil,
                      rate: Float = 0.48,
                      pitch: Float = 0.95) {
        #if canImport(AVFoundation)
        let utterance = AVSpeechUtterance(string: text)
        if let voice, let v = AVSpeechSynthesisVoice(identifier: voice) {
            utterance.voice = v
        } else {
            utterance.voice = Self.defaultVoice()
        }
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        synth.speak(utterance)
        #endif
    }

    public func stop() {
        #if canImport(AVFoundation)
        synth.stopSpeaking(at: .immediate)
        #endif
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    // MARK: - Voice picker helpers

    /// All voices installed on the system, sorted "en-GB premium first → en-GB
    /// enhanced → en-GB default → everything else alphabetical".
    public static func availableVoices() -> [String] {
        #if canImport(AVFoundation)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        return voices.sorted(by: voiceSortOrder).map(\.identifier)
        #else
        return []
        #endif
    }

    /// Best-sounding British voice that's actually installed on this Mac.
    /// Returns nil if no AVFoundation / no voices at all.
    public static func defaultVoice() -> AVSpeechSynthesisVoice? {
        #if canImport(AVFoundation)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let gb = voices.filter { $0.language == "en-GB" }
        if let premium = gb.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = gb.first(where: { $0.quality == .enhanced }) { return enhanced }
        if let anyGB = gb.first { return anyGB }
        // Final fallback — system default in whatever locale.
        return AVSpeechSynthesisVoice(language: Locale.current.identifier)
        #else
        return nil
        #endif
    }

    /// Human-friendly label for the picker: "en-GB · Daniel (Premium)".
    public static func label(for identifier: String) -> String {
        #if canImport(AVFoundation)
        guard let v = AVSpeechSynthesisVoice(identifier: identifier) else {
            return identifier
        }
        let tier: String
        switch v.quality {
        case .premium:  tier = "Premium"
        case .enhanced: tier = "Enhanced"
        default:         tier = "Default"
        }
        return "\(v.language) · \(v.name) (\(tier))"
        #else
        return identifier
        #endif
    }

    #if canImport(AVFoundation)
    private static func voiceSortOrder(_ a: AVSpeechSynthesisVoice,
                                        _ b: AVSpeechSynthesisVoice) -> Bool {
        // en-GB always sorts above non-en-GB.
        let aGB = a.language == "en-GB"
        let bGB = b.language == "en-GB"
        if aGB != bGB { return aGB && !bGB }
        // Within same en-GB-ness, higher quality first.
        if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
        // Then alphabetical by (language, name).
        if a.language != b.language { return a.language < b.language }
        return a.name < b.name
    }
    #endif
}

#if canImport(AVFoundation)
extension TTSService: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                  didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                  didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                  didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
#endif
