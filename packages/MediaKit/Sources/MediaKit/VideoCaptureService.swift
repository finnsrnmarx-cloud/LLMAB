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
public final class VideoCaptureService: NSObject, ObservableObject, @unchecked Sendable {

    #if canImport(AVFoundation)
    public let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "org.llmab.omega.video", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var latestPixelBuffer: CVPixelBuffer?
    #endif

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastError: String?

    /// Watch-mode state — true between `startWatchCapture` and
    /// `stopWatchCapture`. UI reads this to switch the mic button's label
    /// from "watch" → "stop" and render a countdown.
    @Published public private(set) var isWatching: Bool = false

    #if canImport(AVFoundation)
    /// Ring buffer for watch mode. `DispatchQueue.sync`-gated via `queue`
    /// so the capture delegate and the UI see a consistent snapshot.
    private var watchFrames: [(Date, Data)] = []
    private var watchTimer: DispatchSourceTimer?
    private var watchWindowSeconds: Double = 10
    #endif

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

    // MARK: - Watch mode (ring buffer)

    /// Start capturing frames at `intervalSeconds` cadence into a rolling
    /// window of `windowSeconds` total. Frames older than the window are
    /// discarded. Call `snapshotWatchWindow()` at any time to get the
    /// current contents, then `stopWatchCapture()` when done.
    public func startWatchCapture(intervalSeconds: Double = 0.5,
                                  windowSeconds: Double = 10.0) {
        #if canImport(AVFoundation)
        queue.async {
            self.watchFrames.removeAll(keepingCapacity: true)
            self.watchWindowSeconds = windowSeconds
            self.watchTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + intervalSeconds,
                           repeating: intervalSeconds)
            timer.setEventHandler { [weak self] in
                self?.captureWatchFrame()
            }
            timer.resume()
            self.watchTimer = timer
            DispatchQueue.main.async { self.isWatching = true }
        }
        #endif
    }

    public func stopWatchCapture() {
        #if canImport(AVFoundation)
        queue.async {
            self.watchTimer?.cancel()
            self.watchTimer = nil
            DispatchQueue.main.async { self.isWatching = false }
        }
        #endif
    }

    /// Snapshot + clear the ring buffer. Returns frames oldest → newest so
    /// the model sees temporal ordering correctly.
    public func snapshotWatchWindow() -> [Data] {
        #if canImport(AVFoundation)
        queue.sync {
            let sorted = watchFrames.sorted(by: { $0.0 < $1.0 })
            let copy = sorted.map(\.1)
            watchFrames.removeAll(keepingCapacity: true)
            return copy
        }
        #else
        return []
        #endif
    }

    #if canImport(AVFoundation)
    /// Called from the watch timer on `queue`. Encodes the most recent
    /// pixel buffer → JPEG, appends with timestamp, trims past the window.
    private func captureWatchFrame() {
        guard let data = renderLatestAsJPEG() else { return }
        let now = Date()
        watchFrames.append((now, data))
        let cutoff = now.addingTimeInterval(-watchWindowSeconds)
        watchFrames.removeAll(where: { $0.0 < cutoff })
    }

    /// Shared JPEG render path used by both `latestFrameJPEG` and the
    /// watch timer. Runs entirely on `queue` (delegate + timer both enqueue
    /// there), so no extra locking needed.
    private func renderLatestAsJPEG(quality: CGFloat = 0.7) -> Data? {
        #if canImport(CoreImage) && canImport(AppKit)
        guard let buffer = latestPixelBuffer else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg,
                                  properties: [.compressionFactor: quality])
        #else
        return nil
        #endif
    }
    #endif

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
