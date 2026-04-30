import XCTest
import LLMCore
@testable import RuntimeOpenAICompatible

final class DeepSeekRuntimeTests: XCTestCase {
    func testWireBodyEncodesTextToolsAndStripsRuntimePrefix() throws {
        let tool = Tool(
            id: "lookup",
            description: "Look up a thing",
            parameters: ToolParameterSchema(
                properties: ["query": .init(type: "string", description: "Search query")],
                required: ["query"]
            )
        )
        let request = ChatRequest(
            modelId: "deepseek:deepseek-v4-pro",
            messages: [.user("hello")],
            tools: [tool],
            sampling: .deterministic
        )

        let json = try Self.jsonObject(from: DeepSeekRuntime.wireBodyData(for: request))

        XCTAssertEqual(json["model"] as? String, "deepseek-v4-pro")
        XCTAssertEqual(json["stream"] as? Bool, true)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["content"] as? String, "hello")
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "lookup")
    }

    func testWireBodyRejectsImageParts() {
        let request = ChatRequest(
            modelId: "deepseek-v4-flash",
            messages: [Message(role: .user, parts: [
                .text("describe"),
                .image(Data([1, 2]), mimeType: "image/jpeg")
            ])]
        )

        XCTAssertThrowsError(try DeepSeekRuntime.wireBodyData(for: request))
    }

    func testAuthorizationRedactionDoesNotLeakKey() {
        XCTAssertEqual(DeepSeekRuntime.authorizationHeader(apiKey: "sk-secret"), "Bearer sk-secret")
        XCTAssertEqual(DeepSeekRuntime.redactedAuthorizationHeader(), "Bearer ********")
        XCTAssertFalse(DeepSeekRuntime.redactedAuthorizationHeader().contains("sk-secret"))
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
