import XCTest
import LLMCore
@testable import MediaKit

final class VideoFrameSamplerTests: XCTestCase {
    func testSamplerRespectsRateOrderingAndFrameLimit() {
        let start = Date(timeIntervalSince1970: 100)
        let frames = (0..<20).map { idx in
            VideoFrameSample(
                timestamp: start.addingTimeInterval(Double(idx) * 0.1),
                jpegData: Data(repeating: UInt8(idx), count: 10)
            )
        }

        let sampled = VideoFrameSampler().sample(
            frames: frames,
            maxFrameRate: 2,
            maxClipSeconds: 10,
            maxFrames: 3,
            maxPayloadBytes: 10_000
        )

        XCTAssertEqual(sampled.count, 3)
        XCTAssertEqual(sampled.compactMap { $0.jpegData.first }, [UInt8(0), UInt8(5), UInt8(10)])
        XCTAssertTrue(sampled.map(\.timestamp).isSorted())
    }

    func testSamplerRespectsPayloadBudget() {
        let start = Date(timeIntervalSince1970: 200)
        let frames = (0..<5).map { idx in
            VideoFrameSample(
                timestamp: start.addingTimeInterval(Double(idx)),
                jpegData: Data(repeating: 1, count: 100)
            )
        }

        let sampled = VideoFrameSampler().sample(
            frames: frames,
            maxFrameRate: 20,
            maxClipSeconds: 10,
            maxFrames: 5,
            maxPayloadBytes: 250
        )

        XCTAssertEqual(sampled.count, 2)
    }

    func testTurnBuilderExperimentalModeCapsFrames() {
        let start = Date(timeIntervalSince1970: 300)
        let frames = (0..<100).map { idx in
            VideoFrameSample(
                timestamp: start.addingTimeInterval(Double(idx) * 0.05),
                jpegData: Data(repeating: 2, count: 32)
            )
        }

        let selected = VideoTurnBuilder().selectedFrames(
            frames: frames,
            mode: .experimental20FPS,
            profile: .native(maxFrameRate: 20, maxClipSeconds: 3)
        )

        XCTAssertLessThanOrEqual(selected.count, 60)
        XCTAssertTrue(selected.map(\.timestamp).isSorted())
    }
}

private extension Array where Element == Date {
    func isSorted() -> Bool {
        zip(self, dropFirst()).allSatisfy { $0 <= $1 }
    }
}
