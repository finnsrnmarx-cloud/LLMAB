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
    private var latestFrame: VideoFrameSample?
    private var rollingFrames: [VideoFrameSample] = []
    private var lastEncodedFrameAt: Date?
    private var inferenceFrameIntervalSeconds: TimeInterval = 0.05
    private let rollingWindowSeconds: TimeInterval = 12
    private let maxRollingFrames = 240
    #if canImport(CoreImage)
    private let ciContext = CIContext()
    #endif
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
    private var watchStartedAt: Date?
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
                    self.output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    self.session.addOutput(self.output)
                    if let connection = self.output.connection(with: .video),
                       connection.isVideoMinFrameDurationSupported {
                        connection.videoMinFrameDuration = CMTime(value: 1, timescale: 20)
                    }
                }

                self.session.commitConfiguration()
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                    cont.resume()
                }
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
        queue.sync {
            if let latestFrame { return latestFrame.jpegData }
            guard let buffer = latestPixelBuffer else { return nil }
            return renderPixelBufferAsJPEG(buffer, quality: quality)
        }
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
            self.watchStartedAt = Date()
            self.watchWindowSeconds = windowSeconds
            self.inferenceFrameIntervalSeconds = max(0.05, intervalSeconds)
            self.rollingFrames.removeAll(keepingCapacity: true)
            DispatchQueue.main.async { self.isWatching = true }
        }
        #endif
    }

    public func stopWatchCapture() {
        #if canImport(AVFoundation)
        queue.async {
            self.watchStartedAt = nil
            DispatchQueue.main.async { self.isWatching = false }
        }
        #endif
    }

    /// Snapshot + clear the ring buffer. Returns frames oldest → newest so
    /// the model sees temporal ordering correctly.
    public func snapshotWatchWindow() -> [Data] {
        snapshotWatchFrames().map(\.jpegData)
    }

    /// Snapshot + clear the watch buffer as timestamped frames.
    public func snapshotWatchFrames() -> [VideoFrameSample] {
        #if canImport(AVFoundation)
        queue.sync {
            let start = watchStartedAt ?? Date().addingTimeInterval(-watchWindowSeconds)
            let sorted = rollingFrames
                .filter { $0.timestamp >= start }
                .sorted(by: { $0.timestamp < $1.timestamp })
            let copy = sorted
            rollingFrames.removeAll(keepingCapacity: true)
            return copy
        }
        #else
        return []
        #endif
    }

    #if canImport(AVFoundation)
    /// Shared JPEG render path used by both `latestFrameJPEG` and the
    /// frame pipeline. Runs entirely on `queue`, so no extra locking needed.
    private func renderLatestAsJPEG(quality: CGFloat = 0.7) -> Data? {
        guard let buffer = latestPixelBuffer else { return nil }
        return renderPixelBufferAsJPEG(buffer, quality: quality)
    }

    private func renderPixelBufferAsJPEG(_ buffer: CVPixelBuffer,
                                         quality: CGFloat = 0.55,
                                         maxDimension: CGFloat = 512) -> Data? {
        #if canImport(CoreImage) && canImport(AppKit)
        let ci = CIImage(cvPixelBuffer: buffer)
        let extent = ci.extent
        let longestSide = max(extent.width, extent.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let resized = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ciContext.createCGImage(resized, from: resized.extent) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg,
                                  properties: [.compressionFactor: quality])
        #else
        return nil
        #endif
    }

    private func recordFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Date) {
        latestPixelBuffer = pixelBuffer
        if let lastEncodedFrameAt,
           timestamp.timeIntervalSince(lastEncodedFrameAt) < inferenceFrameIntervalSeconds {
            return
        }
        guard let data = renderPixelBufferAsJPEG(pixelBuffer) else { return }
        let sample = VideoFrameSample(timestamp: timestamp, jpegData: data)
        latestFrame = sample
        rollingFrames.append(sample)
        lastEncodedFrameAt = timestamp
        trimRollingFrames(now: timestamp)
    }

    private func trimRollingFrames(now: Date) {
        let cutoff = now.addingTimeInterval(-rollingWindowSeconds)
        rollingFrames.removeAll { $0.timestamp < cutoff }
        if rollingFrames.count > maxRollingFrames {
            rollingFrames.removeFirst(rollingFrames.count - maxRollingFrames)
        }
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
        recordFrame(pb, timestamp: Date())
    }
}
#endif
