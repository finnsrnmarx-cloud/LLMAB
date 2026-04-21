import XCTest
@testable import ModelRegistry
@testable import LLMCore

// MARK: - Stub runtime

/// Minimal LLMRuntime stand-in so ModelRegistry can be exercised without
/// touching the network.
private final class StubRuntime: LLMRuntime, @unchecked Sendable {
    let id: String
    let displayName: String
    let available: Bool
    let models: [ModelInfo]
    let discoveryError: Error?

    init(id: String,
         displayName: String,
         available: Bool = true,
         models: [ModelInfo] = [],
         discoveryError: Error? = nil) {
        self.id = id
        self.displayName = displayName
        self.available = available
        self.models = models
        self.discoveryError = discoveryError
    }

    func isAvailable() async -> Bool { available }

    func discoverModels() async throws -> [ModelInfo] {
        if let err = discoveryError { throw err }
        return models
    }

    func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

final class ModelRegistryTests: XCTestCase {

    func testScanMergesAvailableRuntimes() async {
        let ollamaModels = [
            ModelInfo(id: "ollama:gemma-4:e4b",
                      rawName: "gemma-4:e4b",
                      displayName: "Gemma 4 · E4B",
                      runtimeId: "ollama",
                      family: "gemma-4",
                      variant: "e4b",
                      isLoaded: true)
        ]
        let mlxModels = [
            ModelInfo(id: "mlx:gemma-4-e2b-4bit",
                      rawName: "gemma-4-e2b-4bit",
                      displayName: "Gemma 4 · E2B (MLX)",
                      runtimeId: "mlx",
                      family: "gemma-4",
                      variant: "e2b")
        ]
        let registry = ModelRegistry(runtimes: [
            StubRuntime(id: "ollama", displayName: "Ollama", models: ollamaModels),
            StubRuntime(id: "mlx", displayName: "MLX", models: mlxModels)
        ])

        let snap = await registry.scan()
        XCTAssertEqual(snap.models.count, 2)
        XCTAssertEqual(snap.runtimes.count, 2)
        XCTAssertTrue(snap.runtimes.allSatisfy(\.available))

        // Capability upgrade should have kicked in.
        let e4b = try? XCTUnwrap(snap.models.first { $0.id == "ollama:gemma-4:e4b" })
        XCTAssertEqual(e4b?.capabilities.contextTokens, 256_000)
        XCTAssertTrue(e4b?.capabilities.imageIn == true)
    }

    func testUnavailableRuntimeReportsButDoesntBlockOthers() async {
        let registry = ModelRegistry(runtimes: [
            StubRuntime(id: "ollama", displayName: "Ollama", available: false),
            StubRuntime(id: "mlx", displayName: "MLX", models: [
                ModelInfo(id: "mlx:x", rawName: "x", displayName: "X",
                          runtimeId: "mlx", family: "x")
            ])
        ])
        let snap = await registry.scan()
        XCTAssertEqual(snap.models.count, 1, "only MLX model should survive")
        let ollamaStatus = snap.runtimes.first { $0.id == "ollama" }
        XCTAssertEqual(ollamaStatus?.available, false)
        XCTAssertEqual(ollamaStatus?.modelCount, 0)
    }

    func testDiscoveryErrorSurfaces() async {
        struct BoomError: Error {}
        let registry = ModelRegistry(runtimes: [
            StubRuntime(id: "ollama", displayName: "Ollama", discoveryError: BoomError())
        ])
        let snap = await registry.scan()
        let status = try? XCTUnwrap(snap.runtimes.first)
        XCTAssertTrue(status?.available == true)
        XCTAssertEqual(status?.modelCount, 0)
        XCTAssertNotNil(status?.error)
    }

    func testAcceptingFilter() async {
        let e4b = ModelInfo(id: "ollama:gemma-4:e4b", rawName: "gemma-4:e4b",
                            displayName: "E4B", runtimeId: "ollama",
                            family: "gemma-4", variant: "e4b")
        let b31 = ModelInfo(id: "ollama:gemma-4:31b", rawName: "gemma-4:31b",
                            displayName: "31B", runtimeId: "ollama",
                            family: "gemma-4", variant: "31b")
        let registry = ModelRegistry(runtimes: [
            StubRuntime(id: "ollama", displayName: "Ollama", models: [e4b, b31])
        ])
        let snap = await registry.scan()

        XCTAssertEqual(snap.models(accepting: .audio).map(\.variant), ["e4b"])
        XCTAssertEqual(snap.models(accepting: .video).map(\.variant), ["31b"])
        XCTAssertEqual(snap.models(accepting: .image).count, 2)
    }

    func testResolveReturnsCachedRuntime() async {
        let e4b = ModelInfo(id: "ollama:gemma-4:e4b", rawName: "gemma-4:e4b",
                            displayName: "E4B", runtimeId: "ollama",
                            family: "gemma-4", variant: "e4b")
        let stub = StubRuntime(id: "ollama", displayName: "Ollama", models: [e4b])
        let registry = ModelRegistry(runtimes: [stub])
        _ = await registry.scan()

        let resolved = await registry.resolve(modelId: "ollama:gemma-4:e4b")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.info.variant, "e4b")
        XCTAssertEqual(resolved?.runtime.id, "ollama")
    }
}
