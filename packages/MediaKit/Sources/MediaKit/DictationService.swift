#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Speech)
import Speech
#endif
import Foundation

/// On-device speech-to-text via Apple's Speech framework + AVAudioEngine.
/// Emits live-updated transcription as an `AsyncThrowingStream<String, Error>`
/// where each yielded string is the **full accumulated** transcription so far
/// (not a delta). The stream closes on `isFinal` or on error.
///
/// Deliberately not `@MainActor` so StateObject's autoclosure initialiser
/// has no isolation requirement; all `isListening` updates are dispatched to
/// the main queue before mutating @Published state.
public final class DictationService: ObservableObject {

    @Published public private(set) var isListening: Bool = false

    #if canImport(Speech)
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    #endif

    #if canImport(AVFoundation)
    private let engine = AVAudioEngine()
    #endif

    public init(locale: Locale = .current) {
        #if canImport(Speech)
        self.recognizer = SFSpeechRecognizer(locale: locale)
        #endif
    }

    public func startDictation() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                do {
                    try await self.beginListening(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    public func stop() {
        #if canImport(AVFoundation)
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        #endif
        #if canImport(Speech)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        #endif
        DispatchQueue.main.async { self.isListening = false }
    }

    // MARK: - Internals

    private func beginListening(continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        #if !canImport(Speech) || !canImport(AVFoundation)
        throw MediaKitError.recognizerUnavailable
        #else
        let micOK = await Permissions.requestMicrophone()
        guard micOK else { throw MediaKitError.micPermissionDenied }
        let speechOK = await Permissions.requestSpeechRecognition()
        guard speechOK else { throw MediaKitError.speechPermissionDenied }
        guard let recognizer, recognizer.isAvailable else {
            throw MediaKitError.recognizerUnavailable
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        self.request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw MediaKitError.audioEngineFailure(String(describing: error))
        }

        DispatchQueue.main.async { self.isListening = true }

        self.task = recognizer.recognitionTask(with: req) { result, error in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            if let result {
                continuation.yield(result.bestTranscription.formattedString)
                if result.isFinal {
                    continuation.finish()
                }
            }
        }
        #endif
    }
}
