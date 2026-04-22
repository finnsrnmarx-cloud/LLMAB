#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Speech)
import Speech
#endif
import Foundation

/// On-device speech-to-text via Apple's Speech framework + AVAudioEngine.
///
/// `startDictation()` returns an `AsyncThrowingStream<String, Error>` where
/// each yielded string is the **full accumulated** transcription so far (not
/// a delta). The stream closes on `isFinal` or on error. `stop()` tears down
/// the audio engine, cancels the recognition task, and finalises the stream.
///
/// On-device recognition is preferred (no network, no third-party AI, private).
/// If the requested locale's on-device model isn't installed, we fall back to
/// server-side recognition with `usedOnDevice = false` so the UI can surface
/// a "using Apple cloud" note. Pass `forceOnDevice: true` to reject the
/// fallback and throw `onDeviceRecognitionUnavailable` instead.
///
/// Publishes two observables the UI pulses off:
///   - `isListening` — switches with the audio engine
///   - `audioLevel` — 0.0 – 1.0 RMS envelope, driven from the input tap
///
/// Deliberately not `@MainActor` so `@StateObject` autoclosure construction
/// has no isolation requirement; all published mutations hop to main.
public final class DictationService: ObservableObject, @unchecked Sendable {

    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var audioLevel: Float = 0.0
    @Published public private(set) var usedOnDevice: Bool = true

    #if canImport(Speech)
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    #endif

    #if canImport(AVFoundation)
    private let engine = AVAudioEngine()
    #endif

    private let locale: Locale
    private let forceOnDevice: Bool

    public init(locale: Locale = .current, forceOnDevice: Bool = false) {
        self.locale = locale
        self.forceOnDevice = forceOnDevice
        #if canImport(Speech)
        self.recognizer = SFSpeechRecognizer(locale: locale)
        #endif
    }

    public func startDictation() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if isListening {
                continuation.finish(throwing: MediaKitError.alreadyListening)
                return
            }
            let cancelBox = SendableBox<() -> Void>({ [weak self] in self?.stop() })
            continuation.onTermination = { _ in cancelBox.value() }

            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                do {
                    try await self.beginListening(continuation: continuation)
                } catch {
                    self.stop()
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func stop() {
        #if canImport(AVFoundation)
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        #endif
        #if canImport(Speech)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        #endif
        let finalize: () -> Void = { [weak self] in
            self?.isListening = false
            self?.audioLevel = 0
        }
        if Thread.isMainThread { finalize() }
        else { DispatchQueue.main.async(execute: finalize) }
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

        // Prefer on-device. If the locale's on-device model isn't available,
        // either fall back (default) or fail (forceOnDevice=true).
        let supportsOnDevice = recognizer.supportsOnDeviceRecognition
        if supportsOnDevice {
            req.requiresOnDeviceRecognition = true
        } else if forceOnDevice {
            throw MediaKitError.onDeviceRecognitionUnavailable
        } else {
            req.requiresOnDeviceRecognition = false
        }

        self.request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            self?.updateLevel(from: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw MediaKitError.audioEngineFailure(String(describing: error))
        }

        let usedOnDevice = supportsOnDevice
        DispatchQueue.main.async { [weak self] in
            self?.isListening = true
            self?.usedOnDevice = usedOnDevice
        }

        self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let error {
                continuation.finish(throwing: error)
                self?.stop()
                return
            }
            if let result {
                continuation.yield(result.bestTranscription.formattedString)
                if result.isFinal {
                    continuation.finish()
                    self?.stop()
                }
            }
        }
        #endif
    }

    /// Compute a quick RMS envelope from the raw audio buffer; push to main.
    #if canImport(AVFoundation)
    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sumSquares += sample * sample
        }
        let rms = (sumSquares / Float(frameLength)).squareRoot()
        // Clamp to [0, 1] with a soft knee so quiet mic reads don't hug 0.
        let normalised = min(1.0, max(0.0, rms * 4.0))
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = normalised
        }
    }
    #endif
}

// MARK: - Tiny Sendable helper

/// `AsyncThrowingStream.Continuation.onTermination` expects a `@Sendable`
/// closure. Wrap a plain `() -> Void` in a locked box so we can hand it one
/// without forcing the whole service to be `Sendable`.
private final class SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
