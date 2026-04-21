#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(AppKit)
import AppKit
#endif
import Foundation

/// AVCaptureSession wrapper that exposes a live preview and a `latestFrame`
/// JPEG grab. The Video tab pulls a single frame on demand when the user
/// sends a voice prompt.
///
/// Not `@MainActor` so `@StateObject` construction needs no isolation; the
/// `session` is itself thread-safe per Apple docs.
public final class VideoCaptureService: NSObject, ObservableObject {

    #if canImport(AVFoundation)
    public let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "org.llmab.omega.video", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var latestPixelBuffer: CVPixelBuffer?
    #endif

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastError: String?

    public override init() {
        super.init()
    }

    // MARK: - Control

    public func start() async {
        #if canImport(AVFoundation)
        let ok = await Permissions.requestCamera()
        guard ok else {
            DispatchQueue.main.async { self.lastError = "camera permission denied" }
            return
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                self.session.beginConfiguration()
                self.session.sessionPreset = .vga640x480

                if self.session.inputs.isEmpty,
                   let device = Self.defaultDevice(),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                if self.session.outputs.isEmpty, self.session.canAddOutput(self.output) {
                    self.output.setSampleBufferDelegate(self, queue: self.queue)
                    self.output.alwaysDiscardsLateVideoFrames = true
                    self.session.addOutput(self.output)
                }

                self.session.commitConfiguration()
                self.session.startRunning()
                DispatchQueue.main.async { self.isRunning = true }
                cont.resume()
            }
        }
        #endif
    }

    public func stop() {
        #if canImport(AVFoundation)
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
        #endif
    }

    /// Return the most recent frame as JPEG bytes. Returns nil until the
    /// first frame has arrived.
    public func latestFrameJPEG(quality: CGFloat = 0.7) -> Data? {
        #if canImport(AVFoundation) && canImport(CoreImage)
        guard let buffer = latestPixelBuffer else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        #if canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg,
                                  properties: [.compressionFactor: quality])
        #else
        return nil
        #endif
        #else
        return nil
        #endif
    }

    // MARK: - Device selection

    #if canImport(AVFoundation)
    private static func defaultDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera,
                                for: .video,
                                position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }
    #endif
}

#if canImport(AVFoundation) && canImport(AppKit)
extension VideoCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestPixelBuffer = pb
    }
}
#endif
