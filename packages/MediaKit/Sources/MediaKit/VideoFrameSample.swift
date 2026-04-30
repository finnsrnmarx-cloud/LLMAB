import Foundation
import LLMCore

public struct VideoFrameSample: Sendable, Hashable, Codable {
    public var timestamp: Date
    public var jpegData: Data

    public init(timestamp: Date, jpegData: Data) {
        self.timestamp = timestamp
        self.jpegData = jpegData
    }
}

public enum VideoTurnMode: String, Sendable, Hashable, Codable, CaseIterable {
    case snapshot
    case adaptiveLive
    case experimental20FPS
}

public struct VideoFrameSampler: Sendable {
    public init() {}

    public func sample(frames: [VideoFrameSample],
                       maxFrameRate: Double,
                       maxClipSeconds: Double,
                       maxFrames: Int,
                       maxPayloadBytes: Int) -> [VideoFrameSample] {
        guard maxFrameRate > 0, maxFrames > 0, maxPayloadBytes > 0 else { return [] }
        let sorted = frames.sorted { $0.timestamp < $1.timestamp }
        guard let lastDate = sorted.last?.timestamp else { return [] }

        let clipped = sorted.filter { frame in
            guard maxClipSeconds > 0 else { return true }
            return lastDate.timeIntervalSince(frame.timestamp) <= maxClipSeconds
        }

        let minimumSpacing = 1.0 / maxFrameRate
        var selected: [VideoFrameSample] = []
        var bytes = 0
        var lastSelectedDate: Date?

        for frame in clipped {
            if let lastSelectedDate,
               frame.timestamp.timeIntervalSince(lastSelectedDate) < minimumSpacing {
                continue
            }
            let nextBytes = bytes + frame.jpegData.count
            if nextBytes > maxPayloadBytes { break }
            selected.append(frame)
            bytes = nextBytes
            lastSelectedDate = frame.timestamp
            if selected.count >= maxFrames { break }
        }

        return selected
    }
}

public struct VideoTurnBuilder: Sendable {
    public var sampler: VideoFrameSampler

    public init(sampler: VideoFrameSampler = VideoFrameSampler()) {
        self.sampler = sampler
    }

    public func parts(frames: [VideoFrameSample],
                      userText: String,
                      mode: VideoTurnMode,
                      profile: VideoIngestionProfile) -> [ContentPart] {
        let selected = selectedFrames(
            frames: frames,
            mode: mode,
            profile: profile
        )

        var parts = selected.map { ContentPart.image($0.jpegData, mimeType: "image/jpeg") }
        parts.append(.text(promptText(
            userText: userText,
            mode: mode,
            frameCount: selected.count,
            profile: profile
        )))
        return parts
    }

    public func selectedFrames(frames: [VideoFrameSample],
                               mode: VideoTurnMode,
                               profile: VideoIngestionProfile) -> [VideoFrameSample] {
        switch mode {
        case .snapshot:
            return Array(frames.sorted { $0.timestamp < $1.timestamp }.suffix(1))
        case .adaptiveLive:
            let rate = max(1, min(profile.maxFrameRate == 0 ? 2 : profile.maxFrameRate, 4))
            let seconds = max(1, min(profile.maxClipSeconds == 0 ? 10 : profile.maxClipSeconds, 10))
            return sampler.sample(
                frames: frames,
                maxFrameRate: rate,
                maxClipSeconds: seconds,
                maxFrames: min(Int(rate * seconds), 40),
                maxPayloadBytes: 4_000_000
            )
        case .experimental20FPS:
            let seconds = max(1, min(profile.maxClipSeconds == 0 ? 3 : profile.maxClipSeconds, 3))
            return sampler.sample(
                frames: frames,
                maxFrameRate: 20,
                maxClipSeconds: seconds,
                maxFrames: 60,
                maxPayloadBytes: 8_000_000
            )
        }
    }

    private func promptText(userText: String,
                            mode: VideoTurnMode,
                            frameCount: Int,
                            profile: VideoIngestionProfile) -> String {
        let spokenClause = userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "The user did not speak during this capture."
            : "The user said: \"\(userText)\"."

        switch mode {
        case .snapshot:
            return "Live camera snapshot. \(spokenClause) Answer concisely for speech playback."
        case .adaptiveLive:
            return """
            Adaptive live camera context. You received \(frameCount) ordered JPEG keyframes, sampled from a live camera stream. \(spokenClause) Interpret them as a short clip and focus on changes over time. Reply in at most 3 spoken sentences.
            """
        case .experimental20FPS:
            return """
            Experimental 20fps camera context. You received \(frameCount) ordered JPEG frames from a short high-rate capture window. The selected model advertises up to \(Int(profile.maxFrameRate)) fps or native video ingest. \(spokenClause) Focus on motion and temporal events. Reply in at most 3 spoken sentences.
            """
        }
    }
}
