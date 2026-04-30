import Foundation
import LLMCore
import MediaKit
import ModelRegistry
import SwiftUI

/// Drives the Video tab: camera capture + dictation + VLM + TTS.
///
/// Flow:
/// 1. `startSession()` brings up the camera preview.
/// 2. User holds the mic; DictationService streams transcription.
/// 3. On release, we grab `latestFrameJPEG`, build a `Message` with
///    (image + "user said: …"), send to the selected video-capable model,
///    stream the reply, and hand the final reply to TTSService.
/// 4. Loop back to step 2.
@MainActor
final class VideoTabViewModel: ObservableObject {

    @Published var transcript: [Exchange] = []
    @Published var isListening: Bool = false
    @Published var isReplying: Bool = false
    @Published var error: String?
    @Published var liveTranscription: String = ""
    @Published var isSessionRunning: Bool = false

    /// Watch-mode state. `isWatching` flips for the duration of a watch
    /// window (default 10 s); `watchSecondsRemaining` drives the UI
    /// countdown.
    @Published var isWatching: Bool = false
    @Published var watchSecondsRemaining: Double = 0
    @Published var clipMode: VideoTurnMode = .adaptiveLive

    /// Capture runs near 20 fps; the turn builder decides how aggressively to
    /// sample frames for the selected mode/model.
    private let captureFrameIntervalSeconds: Double = 0.05
    private let adaptiveWindowSeconds: Double = 10.0
    private let experimentalWindowSeconds: Double = 3.0
    private let turnBuilder = VideoTurnBuilder()

    private var activeWatchWindowSeconds: Double {
        clipMode == .experimental20FPS ? experimentalWindowSeconds : adaptiveWindowSeconds
    }

    struct Exchange: Identifiable {
        let id = UUID()
        var user: String
        var assistant: String
    }

    let capture = VideoCaptureService()
    private let dictation = DictationService()
    private var dictationTask: Task<Void, Never>?
    private var replyTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var watchCountdownTask: Task<Void, Never>?
    private weak var store: AppStore?
    private weak var tts: TTSService?

    func bind(store: AppStore, tts: TTSService) {
        self.store = store
        self.tts = tts
    }

    // MARK: - Capture lifecycle

    func startSession() async {
        error = nil
        await capture.start()
        isSessionRunning = capture.isRunning
    }

    func stopSession() {
        stopListening()
        // Cancel an in-flight watch so we don't continue ticking against a
        // dead capture session.
        watchTask?.cancel()
        watchCountdownTask?.cancel()
        watchTask = nil
        watchCountdownTask = nil
        capture.stopWatchCapture()
        isWatching = false
        watchSecondsRemaining = 0

        capture.stop()
        isSessionRunning = false
    }

    // MARK: - Turn control

    func startListening() {
        guard !isListening, !isReplying else { return }
        isListening = true
        liveTranscription = ""
        dictationTask = Task { @MainActor in
            do {
                for try await text in dictation.startDictation() {
                    liveTranscription = text
                }
            } catch {
                self.error = String(describing: error)
            }
        }
    }

    func stopListening() {
        dictation.stop()
        dictationTask?.cancel()
        dictationTask = nil
        isListening = false

        let prompt = liveTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        sendTurn(userText: prompt)
    }

    private func sendTurn(userText: String) {
        guard !isReplying else { return }
        let frame = capture.latestFrameJPEG()
        transcript.append(Exchange(user: userText, assistant: ""))
        isReplying = true

        replyTask = Task { [weak self] in
            await self?.runReply(userText: userText, frame: frame)
        }
    }

    // MARK: - Watch mode

    /// Start a watch window: camera fills a near-20fps ring buffer; dictation
    /// runs in parallel to capture what the user
    /// says during the clip. At window expiry (or early stop), all frames
    /// + the transcript ship to the model in one multi-image request.
    func startWatch() {
        guard !isWatching, !isListening, !isReplying else { return }
        isWatching = true
        liveTranscription = ""

        let windowSeconds = activeWatchWindowSeconds
        watchSecondsRemaining = windowSeconds

        // Ring buffer + dictation in parallel. We capture near 20 fps even
        // for adaptive mode, then downsample to fit the model profile.
        capture.startWatchCapture(intervalSeconds: captureFrameIntervalSeconds,
                                  windowSeconds: windowSeconds)
        dictationTask = Task { @MainActor in
            do {
                for try await text in dictation.startDictation() {
                    liveTranscription = text
                }
            } catch {
                self.error = String(describing: error)
            }
        }

        // Countdown ticker → drives the UI.
        watchCountdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let start = Date()
            let duration = self.activeWatchWindowSeconds
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let remaining = max(0, duration - elapsed)
                self.watchSecondsRemaining = remaining
                if remaining <= 0 { break }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
            }
        }

        // Main watch task: waits for timeout or early-cancel, then submits.
        watchTask = Task { [weak self] in
            guard let self else { return }
            let duration = await MainActor.run { self.activeWatchWindowSeconds }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.finishWatch()
        }
    }

    /// Early-stop: submit whatever's in the ring buffer right now.
    func stopWatchEarly() {
        guard isWatching else { return }
        watchTask?.cancel()
        watchTask = nil
        Task { @MainActor [weak self] in
            await self?.finishWatch()
        }
    }

    /// Close out dictation + ring buffer, then ship a multi-image turn.
    private func finishWatch() async {
        // Stop producers first so we don't race the snapshot.
        dictation.stop()
        dictationTask?.cancel()
        dictationTask = nil

        capture.stopWatchCapture()
        let frames = capture.snapshotWatchFrames()

        watchCountdownTask?.cancel()
        watchCountdownTask = nil
        watchSecondsRemaining = 0
        isWatching = false

        let userText = liveTranscription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscription = ""

        let displayUser = userText.isEmpty
            ? "[\(clipModeLabel) · no speech]"
            : userText
        transcript.append(Exchange(user: displayUser, assistant: ""))
        isReplying = true
        await runWatchReply(userText: userText, frames: frames, mode: clipMode)
        isReplying = false
    }

    private func runWatchReply(userText: String,
                               frames: [VideoFrameSample],
                               mode: VideoTurnMode) async {
        guard let store else { return }
        guard let resolved = await store.selected else {
            error = "no model selected"
            return
        }
        let (runtime, info) = resolved
        let profile = info.capabilities.videoProfile

        guard !frames.isEmpty else {
            error = "no camera frames captured yet"
            return
        }

        guard info.capabilities.imageIn || profile.snapshot || profile.sampledClip || profile.nativeVideo else {
            error = "\(info.displayName) can't accept frames — pick a vision-capable model"
            return
        }

        if mode == .experimental20FPS,
           !profile.nativeVideo,
           profile.maxFrameRate < 20 {
            error = "\(info.displayName) is not marked 20fps-capable — use adaptive live or switch models"
            return
        }

        let parts = turnBuilder.parts(
            frames: frames,
            userText: userText,
            mode: mode,
            profile: profile
        )

        let request = ChatRequest(
            modelId: info.id,
            messages: [.system(Self.systemPrompt), Message(role: .user, parts: parts)],
            sampling: .balanced,
            stream: true
        )

        var full = ""
        do {
            for try await chunk in runtime.chat(request) {
                if Task.isCancelled { return }
                if case .text(let delta) = chunk {
                    full += delta
                    if let idx = transcript.indices.last {
                        transcript[idx].assistant += delta
                    }
                }
            }
        } catch {
            self.error = String(describing: error)
            return
        }

        tts?.speak(full)
    }

    private func runReply(userText: String, frame: Data?) async {
        defer { isReplying = false }

        guard let store else { return }
        guard let resolved = await store.selected else {
            error = "no model selected"
            return
        }
        let (runtime, info) = resolved

        guard info.capabilities.imageIn || info.capabilities.videoProfile.snapshot else {
            error = "\(info.displayName) can't accept images — switch to any vision-capable model (Gemma 4 E4B / 26B / 31B, Qwen 3 VL, MiniCPM-V, …)"
            return
        }

        let frames = frame.map { [VideoFrameSample(timestamp: Date(), jpegData: $0)] } ?? []
        let parts = turnBuilder.parts(
            frames: frames,
            userText: userText,
            mode: .snapshot,
            profile: info.capabilities.videoProfile
        )

        let request = ChatRequest(
            modelId: info.id,
            messages: [.system(Self.systemPrompt), Message(role: .user, parts: parts)],
            sampling: .balanced,
            stream: true
        )

        var full = ""
        do {
            for try await chunk in runtime.chat(request) {
                if Task.isCancelled { return }
                if case .text(let delta) = chunk {
                    full += delta
                    if let idx = transcript.indices.last {
                        transcript[idx].assistant += delta
                    }
                }
            }
        } catch {
            self.error = String(describing: error)
            return
        }

        tts?.speak(full)
    }

    private static let systemPrompt = """
    You are ω, an on-device video-chat assistant. You see a frame from the \
    user's camera and hear what they say. Keep answers short and spoken, \
    one to two sentences, as if on a phone call.
    """

    private var clipModeLabel: String {
        switch clipMode {
        case .snapshot:
            "snapshot"
        case .adaptiveLive:
            "adaptive live"
        case .experimental20FPS:
            "20fps experimental"
        }
    }
}
