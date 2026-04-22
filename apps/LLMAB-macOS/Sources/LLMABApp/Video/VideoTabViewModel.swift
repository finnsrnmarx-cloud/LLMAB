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

    struct Exchange: Identifiable {
        let id = UUID()
        var user: String
        var assistant: String
    }

    let capture = VideoCaptureService()
    private let dictation = DictationService()
    private var dictationTask: Task<Void, Never>?
    private var replyTask: Task<Void, Never>?
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

    private func runReply(userText: String, frame: Data?) async {
        defer { isReplying = false }

        guard let store else { return }
        guard let resolved = await store.selected else {
            error = "no model selected"
            return
        }
        let (runtime, info) = resolved

        guard info.capabilities.videoIn || info.capabilities.imageIn else {
            error = "\(info.displayName) can't accept images — switch to any vision-capable model (Gemma 4 E4B / 26B / 31B, Qwen 3 VL, MiniCPM-V, …)"
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
