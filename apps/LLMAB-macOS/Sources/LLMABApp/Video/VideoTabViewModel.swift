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

    /// Watch window config (tunable via future settings). 10 s × 2 Hz = 20
    /// frames per submission — ~2 MB request payload at VGA JPEG quality 0.7.
    private let watchWindowSeconds: Double = 10.0
    private let watchIntervalSeconds: Double = 0.5

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

    /// Start a watch window: camera fills a ring buffer (frame every 0.5 s,
    /// up to 10 s); dictation runs in parallel to capture what the user
    /// says during the clip. At window expiry (or early stop), all frames
    /// + the transcript ship to the model in one multi-image request.
    func startWatch() {
        guard !isWatching, !isListening, !isReplying else { return }
        isWatching = true
        liveTranscription = ""
        watchSecondsRemaining = watchWindowSeconds

        // Ring buffer + dictation in parallel.
        capture.startWatchCapture(intervalSeconds: watchIntervalSeconds,
                                  windowSeconds: watchWindowSeconds)
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
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let remaining = max(0, self.watchWindowSeconds - elapsed)
                self.watchSecondsRemaining = remaining
                if remaining <= 0 { break }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
            }
        }

        // Main watch task: waits for timeout or early-cancel, then submits.
        watchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.watchWindowSeconds * 1_000_000_000))
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
        let frames = capture.snapshotWatchWindow()

        watchCountdownTask?.cancel()
        watchCountdownTask = nil
        watchSecondsRemaining = 0
        isWatching = false

        let userText = liveTranscription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscription = ""

        let displayUser = userText.isEmpty
            ? "[watched \(Int(watchWindowSeconds))s, no speech]"
            : userText
        transcript.append(Exchange(user: displayUser, assistant: ""))
        isReplying = true
        await runWatchReply(userText: userText, frames: frames)
        isReplying = false
    }

    private func runWatchReply(userText: String, frames: [Data]) async {
        guard let store else { return }
        guard let resolved = await store.selected else {
            error = "no model selected"
            return
        }
        let (runtime, info) = resolved

        guard info.capabilities.videoIn || info.capabilities.imageIn else {
            error = "\(info.displayName) can't accept frames — pick a vision-capable model"
            return
        }

        var parts: [ContentPart] = []
        for frame in frames {
            parts.append(.image(frame, mimeType: "image/jpeg"))
        }
        let spokenClause = userText.isEmpty
            ? "The user didn't say anything in these \(Int(watchWindowSeconds)) seconds — describe what happened."
            : "While the camera rolled the user said: \"\(userText)\"."
        parts.append(.text("""
        You've been handed \(frames.count) JPEG frames captured at \
        \(Int(1.0 / watchIntervalSeconds)) Hz over the last \
        \(Int(watchWindowSeconds)) seconds, in chronological order. \
        Interpret them as a short video clip. \(spokenClause) \
        Reply concisely for speech playback (≤ 3 sentences). \
        Focus on *change over time* — what moved, appeared, or happened.
        """))

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

        guard info.capabilities.videoIn || info.capabilities.imageIn else {
            error = "\(info.displayName) cannot accept frames — switch to Gemma 4 26B / 31B"
            return
        }

        var parts: [ContentPart] = []
        if let frame {
            parts.append(.image(frame, mimeType: "image/jpeg"))
        }
        parts.append(.text(
            "Live camera context. The user just said: \"\(userText)\". "
            + "Answer concisely for speech playback (≤ 2 sentences)."
        ))

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
}
