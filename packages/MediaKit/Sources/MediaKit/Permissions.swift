#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Speech)
import Speech
#endif
import Foundation

/// Thin wrappers over the system permission prompts we need.
/// All calls are safe to invoke multiple times — the OS prompts only on the
/// first request and returns the cached decision thereafter.
public enum Permissions {

    /// Microphone permission — required before any audio capture.
    @MainActor
    public static func requestMicrophone() async -> Bool {
        #if canImport(AVFoundation)
        if #available(macOS 14.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        #else
        return false
        #endif
    }

    /// Apple Speech framework authorization (on-device recognition).
    @MainActor
    public static func requestSpeechRecognition() async -> Bool {
        #if canImport(Speech)
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        #else
        return false
        #endif
    }

    /// Camera permission — required by the Video tab.
    @MainActor
    public static func requestCamera() async -> Bool {
        #if canImport(AVFoundation)
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                cont.resume(returning: granted)
            }
        }
        #else
        return false
        #endif
    }
}
