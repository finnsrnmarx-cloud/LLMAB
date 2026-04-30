import XCTest
import LLMCore
@testable import RuntimeLlamaCpp

final class RuntimeLlamaCppTests: XCTestCase {

    func testWireBodyEncodesImageContentBlocks() throws {
        let request = ChatRequest(
            modelId: "llamacpp:gemma-4-e4b",
            messages: [
                Message(role: .user, parts: [
                    .text("describe this"),
                    .image(Data([0xCA, 0xFE]), mimeType: "image/jpeg")
                ])
            ],
            sampling: .deterministic
        )

        let json = try Self.jsonObject(from: LlamaCppRuntime.wireBodyData(for: request))

        XCTAssertEqual(json["model"] as? String, "gemma-4-e4b")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "describe this")
        XCTAssertEqual(content.last?["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(content.last?["image_url"] as? [String: Any])
        XCTAssertEqual(imageURL["url"] as? String, "data:image/jpeg;base64,yv4=")
    }

    func testWireBodyMapsToolsAndToolHistory() throws {
        let schema = ToolParameterSchema(
            properties: [
                "path": .init(type: "string", description: "File path")
            ],
            required: ["path"]
        )
        let call = ToolCall(
            id: "call-1",
            toolId: "read_file",
            argumentsJSON: Data(#"{"path":"README.md"}"#.utf8)
        )
        let request = ChatRequest(
            modelId: "gemma-4-e4b",
            messages: [
                Message(role: .assistant, toolCalls: [call]),
                Message(role: .tool, parts: [.text("hello")], toolCallId: "call-1")
            ],
            tools: [
                Tool(id: "read_file", description: "Read a file", parameters: schema)
            ]
        )

        let json = try Self.jsonObject(from: LlamaCppRuntime.wireBodyData(for: request))

        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "read_file")

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let toolCalls = try XCTUnwrap(messages.first?["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(toolCalls.first?["id"] as? String, "call-1")
        let callFunction = try XCTUnwrap(toolCalls.first?["function"] as? [String: Any])
        XCTAssertEqual(callFunction["name"] as? String, "read_file")
        XCTAssertEqual(callFunction["arguments"] as? String, #"{"path":"README.md"}"#)
        XCTAssertEqual(messages.last?["tool_call_id"] as? String, "call-1")
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
