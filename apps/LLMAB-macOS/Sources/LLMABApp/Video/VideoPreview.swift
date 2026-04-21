import SwiftUI
import MediaKit
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AppKit)
import AppKit
#endif

/// NSViewRepresentable that shows the VideoCaptureService's live preview via
/// AVCaptureVideoPreviewLayer.
struct VideoPreview: NSViewRepresentable {
    let service: VideoCaptureService

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        #if canImport(AVFoundation) && canImport(AppKit)
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: service.session)
        preview.videoGravity = .resizeAspectFill
        view.layer = preview
        #endif
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        override var isFlipped: Bool { true }
    }
}
