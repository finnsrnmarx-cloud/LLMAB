import SwiftUI
import UIKitOmega

/// Video tab — live camera + mic → Gemma 4 26B/31B → TTS response. Requires
/// either 26B or 31B; UI is disabled under E-series. Real AVCaptureSession
/// pipeline lands in chunk 13.
struct VideoTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TabHeader("Video",
                      subtitle: "live · aurora-full · requires 26B / 31B",
                      palette: .full)

            PlaceholderCard(
                title: "Ships in chunk 13",
                body: "AVCaptureSession at 1 fps → frame batches to Gemma 4 26B or 31B. Parallel mic → ASR. AVSpeechSynthesizer TTS response. A spinning ω sits in the preview corner while capture is live; the tab gates on model capability (disabled with tooltip on E-series).",
                palette: .full
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
