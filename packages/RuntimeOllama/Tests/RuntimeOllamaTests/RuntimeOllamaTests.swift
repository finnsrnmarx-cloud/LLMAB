import XCTest
@testable import RuntimeOllama
@testable import LLMCore

final class RuntimeOllamaTests: XCTestCase {

    // MARK: - Name parsing

    func testParseFamilyFromGemmaTag() {
        let (family, variant) = OllamaRuntime.parseFamily(
            fromRawName: "gemma-4:e4b",
            reportedFamily: "gemma"
        )
        XCTAssertEqual(family, "gemma")
        XCTAssertEqual(variant, "e4b")
    }

    func testParseFamilyFallsBackToHeadWhenNoReportedFamily() {
        let (family, variant) = OllamaRuntime.parseFamily(
            fromRawName: "gemma-4:31b",
            reportedFamily: nil
        )
        XCTAssertEqual(family, "gemma-4")
        XCTAssertEqual(variant, "31b")
    }

    func testParseFamilyWithNoTag() {
        let (family, variant) = OllamaRuntime.parseFamily(
            fromRawName: "llama3",
            reportedFamily: nil
        )
        XCTAssertEqual(family, "llama3")
        XCTAssertNil(variant)
    }

    // MARK: - Humanize

    func testHumanizeGemma4() {
        let s = OllamaRuntime.humanize("gemma-4:e4b", paramSize: "4.5B")
        XCTAssertEqual(s, "Gemma 4 · E4B (4.5B)")
    }

    func testHumanizeNoSize() {
        let s = OllamaRuntime.humanize("gemma-4:31b", paramSize: nil)
        XCTAssertEqual(s, "Gemma 4 · 31B")
    }

    // MARK: - Wire body translation

    func testWireBodyStripsRuntimePrefix() throws {
        let req = ChatRequest(
            modelId: "ollama:gemma-4:e4b",
            messages: [.user("hi")]
        )
        let body = try OllamaRuntime.toWireBody(req)
        XCTAssertEqual(body.model, "gemma-4:e4b")
        XCTAssertEqual(body.messages.count, 1)
        XCTAssertEqual(body.messages.first?.role, "user")
        XCTAssertEqual(body.messages.first?.content, "hi")
        XCTAssertTrue(body.stream)
    }

    func testWireBodyPreservesBareModelName() throws {
        let req = ChatRequest(modelId: "gemma-4:e4b", messages: [.user("hi")])
        let body = try OllamaRuntime.toWireBody(req)
        XCTAssertEqual(body.model, "gemma-4:e4b")
    }

    func testWireBodyBase64EncodesImageParts() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let req = ChatRequest(
            modelId: "gemma-4:e4b",
            messages: [Message(role: .user, parts: [
                .text("describe "),
                .image(png, mimeType: "image/png"),
                .text("this")
            ])]
        )
        let body = try OllamaRuntime.toWireBody(req)
        let message = try XCTUnwrap(body.messages.first)
        XCTAssertEqual(message.content, "describe this")
        XCTAssertEqual(message.images?.count, 1)
        XCTAssertEqual(message.images?.first, png.base64EncodedString())
    }

    func testWireBodyMapsToolsToOpenAIShape() throws {
        let tool = Tool(
            id: "read_file",
            description: "Read a file",
            parameters: ToolParameterSchema(
                type: "object",
                properties: ["path": .init(type: "string", description: "absolute path")],
                required: ["path"]
            )
        )
        let req = ChatRequest(modelId: "gemma-4:e4b",
                              messages: [.user("read a.txt")],
                              tools: [tool])
        let body = try OllamaRuntime.toWireBody(req)
        XCTAssertEqual(body.tools?.count, 1)
        XCTAssertEqual(body.tools?.first?.type, "function")
        XCTAssertEqual(body.tools?.first?.function.name, "read_file")
        XCTAssertEqual(body.tools?.first?.function.parameters.required, ["path"])
    }

    func testWireBodyDropsAudioAndVideoParts() throws {
        let req = ChatRequest(
            modelId: "gemma-4:e4b",
            messages: [Message(role: .user, parts: [
                .text("transcribe "),
                .audio(Data([0x01, 0x02]), mimeType: "audio/wav"),
                .text("this clip")
            ])]
        )
        let body = try OllamaRuntime.toWireBody(req)
        let message = try XCTUnwrap(body.messages.first)
        XCTAssertEqual(message.content, "transcribe this clip")
        XCTAssertNil(message.images)
    }

    // MARK: - Default endpoint

    func testDefaultEndpointIsLocalhost11434() {
        XCTAssertEqual(RuntimeOllama.defaultEndpoint.absoluteString,
                       "http://127.0.0.1:11434")
    }
}
