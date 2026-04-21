import XCTest
@testable import LLMCore

final class LLMCoreTests: XCTestCase {

    // MARK: - Version

    func testVersionIsSet() {
        XCTAssertFalse(LLMCore.version.isEmpty)
    }

    // MARK: - Modality

    func testModalityIsExhaustive() {
        XCTAssertEqual(Modality.allCases.count, 4)
        XCTAssertTrue(Modality.allCases.contains(.video))
    }

    // MARK: - Capabilities

    func testCapabilitiesAcceptsAndEmits() {
        let gemma4E = ModelCapabilities(
            textIn: true, textOut: true,
            imageIn: true, imageOut: false,
            audioIn: true, audioOut: false,
            videoIn: false, videoOut: false,
            toolUse: true, thinking: true,
            contextTokens: 256_000
        )
        XCTAssertTrue(gemma4E.accepts(.text))
        XCTAssertTrue(gemma4E.accepts(.image))
        XCTAssertTrue(gemma4E.accepts(.audio))
        XCTAssertFalse(gemma4E.accepts(.video))
        XCTAssertFalse(gemma4E.emits(.image))
        XCTAssertEqual(gemma4E.contextTokens, 256_000)
    }

    // MARK: - Message

    func testMessageTextContentConcatenates() {
        let m = Message(role: .user, parts: [
            .text("hello "),
            .image(Data(), mimeType: "image/png"),
            .text("world")
        ])
        XCTAssertEqual(m.textContent, "hello world")
    }

    func testMessageHelpers() {
        XCTAssertEqual(Message.user("hi").role, .user)
        XCTAssertEqual(Message.system("be concise").role, .system)
        XCTAssertEqual(Message.assistant("ok").role, .assistant)
    }

    // MARK: - ChatRequest encoding

    func testChatRequestRoundTrip() throws {
        let req = ChatRequest(
            modelId: "ollama:gemma-4:e4b",
            messages: [.user("hi")],
            sampling: .deterministic,
            stream: true
        )
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(ChatRequest.self, from: data)
        XCTAssertEqual(decoded.modelId, req.modelId)
        XCTAssertEqual(decoded.messages.first?.textContent, "hi")
    }

    // MARK: - Pull progress fraction

    func testPullProgressFraction() {
        var p = PullProgress(status: "downloading",
                             downloadedBytes: 500, totalBytes: 1000)
        XCTAssertEqual(p.fraction, 0.5)
        p = PullProgress(status: "queued")
        XCTAssertNil(p.fraction)
    }
}
