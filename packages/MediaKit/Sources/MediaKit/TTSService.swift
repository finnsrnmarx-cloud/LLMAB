#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// System text-to-speech wrapper. Uses AVSpeechSynthesizer — fully on-device,
/// free, offline. A future opt-in upgrade is Kokoro-TTS or Parakeet via MLX.
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

    public func speak(_ text: String, voice: String? = nil, rate: Float = 0.5) {
        #if canImport(AVFoundation)
        let utterance = AVSpeechUtterance(string: text)
        if let voice, let v = AVSpeechSynthesisVoice(identifier: voice) {
            utterance.voice = v
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        }
        utterance.rate = rate
        synth.speak(utterance)
        #endif
    }

    public func stop() {
        #if canImport(AVFoundation)
        synth.stopSpeaking(at: .immediate)
        #endif
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    public static func availableVoices() -> [String] {
        #if canImport(AVFoundation)
        return AVSpeechSynthesisVoice.speechVoices().map(\.identifier)
        #else
        return []
        #endif
    }
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
