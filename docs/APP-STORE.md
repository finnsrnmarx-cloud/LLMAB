# LLMAB — Apple distribution notes

## Posture

LLMAB is **local-first**: by default, LLM inference runs on-device or loopback via a runtime (Ollama, MLX, llama.cpp) the user installs. No user data is sent to any third-party AI service unless the user explicitly configures an opt-in cloud provider such as DeepSeek.

### Guideline 5.1.2(i) — third-party AI

Apple tightened 5.1.2(i) in late 2025 / early 2026 to require explicit user consent and per-surface disclosure before sharing personal data with third-party AI (OpenAI, Gemini, Claude cloud, DeepSeek cloud, etc.). **On-device inference using Core ML, Create ML, or equivalent frameworks is exempt.** LLMAB's local runtime adapters talk to `127.0.0.1` only; they fall under the exemption.

Optional cloud adapters must have:
- Provider-specific API key setup in Keychain.
- Clear provider copy before configuration.
- Always-visible "cloud" badges on provider/model rows and active chat headers.
- No camera/video capability unless the provider has an explicit supported multimodal API mapping.

## V1 distribution: Developer ID + direct DMG

V1 targets **Developer ID signing + notarization + DMG download**, not the Mac App Store. Reasons:

1. The **Code tab** needs broad filesystem access to analyze user repositories. Security-scoped bookmarks work, but full-disk access entitlements are only available to directly-distributed apps.
2. The **Agents tab** runs shell commands; this is incompatible with App Sandbox without a helper tool.
3. Faster iteration during v1.

A sandboxed App Store build is planned post-v1 with reduced capability (Code tab limited to security-scoped folders, Agents tab allowlist narrowed).

### Notarization checklist

- Hardened Runtime on.
- `com.apple.security.cs.disable-library-validation` **only** if we need to load MLX / llama.cpp dynamic libraries at runtime.
- `com.apple.security.device.camera`, `.audio-input`, `.speech-recognition` entitlements.
- `altool --notarize-app` / `notarytool submit`, staple the ticket.

## Required Info.plist strings

| Key                                       | Value                                                             |
|-------------------------------------------|-------------------------------------------------------------------|
| `NSCameraUsageDescription`                | "ω uses the camera for the Video tab. Frames are processed by selected local vision models; current cloud text providers do not receive camera frames." |
| `NSMicrophoneUsageDescription`            | "ω uses the microphone for dictation and live conversation. Audio transcription is on-device; text may be sent if you select an opt-in cloud model." |
| `NSSpeechRecognitionUsageDescription`     | "ω transcribes your voice on-device with Apple Speech."           |
| `NSDesktopFolderUsageDescription`         | "ω opens folders you choose in the Code tab for local analysis." |
| `NSDocumentsFolderUsageDescription`       | "ω opens folders you choose in the Code tab for local analysis." |
| `NSDownloadsFolderUsageDescription`       | "ω opens folders you choose in the Code tab for local analysis." |
| `NSAppleEventsUsageDescription`           | "ω can run approved shell commands when you enable the Agents tab." |

## Privacy manifest (`PrivacyInfo.xcprivacy`)

- `NSPrivacyTracking`: `false`.
- `NSPrivacyCollectedDataTypes`: empty — we collect nothing.
- `NSPrivacyAccessedAPITypes`:
  - `NSPrivacyAccessedAPICategoryFileTimestamp` — reason `C617.1` (inside the container, displaying file metadata in the Code tab).
  - `NSPrivacyAccessedAPICategoryUserDefaults` — reason `CA92.1` (app settings).

## App Sandbox (for later MAS build)

Entitlements needed even with sandbox:

- `com.apple.security.app-sandbox` = true
- `com.apple.security.network.client` = true  *(loopback to Ollama / llama-server; HTTPS for explicitly configured cloud providers)*
- `com.apple.security.device.camera` = true
- `com.apple.security.device.audio-input` = true
- `com.apple.security.files.user-selected.read-write` = true
- `com.apple.security.files.bookmarks.app-scope` = true

Loopback `127.0.0.1:11434` traffic is permitted with `network.client`. If cloud providers are enabled in an App Store build, outbound HTTPS must be disclosed in review notes and the in-app privacy copy.

## Review notes to include

- "By default, AI inference is on-device/loopback via user-installed runtimes (Ollama / MLX / llama.cpp). Optional cloud providers require user-supplied API keys and are visibly badged."
- "No data is collected from users."
- "Network access is used for loopback local-runtime communication and, only when configured, HTTPS calls to the selected cloud provider."
