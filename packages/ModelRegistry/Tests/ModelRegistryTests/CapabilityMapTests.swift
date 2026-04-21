import XCTest
@testable import ModelRegistry
@testable import LLMCore

final class CapabilityMapTests: XCTestCase {

    // MARK: - Gemma 4 variants

    func testGemma4E4BIsRecommendedAndAudioCapable() {
        let info = ModelInfo(
            id: "ollama:gemma-4:e4b",
            rawName: "gemma-4:e4b",
            displayName: "Gemma 4 · E4B",
            runtimeId: "ollama",
            family: "gemma-4",
            variant: "e4b"
        )
        let caps = CapabilityMap.capabilities(for: info)
        XCTAssertTrue(caps.textIn)
        XCTAssertTrue(caps.imageIn)
        XCTAssertTrue(caps.audioIn)
        XCTAssertFalse(caps.videoIn, "E4B should not claim video support")
        XCTAssertTrue(caps.thinking)
        XCTAssertTrue(caps.toolUse)
        XCTAssertEqual(caps.contextTokens, 256_000)
        XCTAssertTrue(caps.tags.contains("recommended"))
    }

    func testGemma4_31BVideoYesAudioNo() {
        let info = ModelInfo(
            id: "ollama:gemma-4:31b",
            rawName: "gemma-4:31b",
            displayName: "Gemma 4 · 31B",
            runtimeId: "ollama",
            family: "gemma-4",
            variant: "31b"
        )
        let caps = CapabilityMap.capabilities(for: info)
        XCTAssertFalse(caps.audioIn, "dense 31B has no native audio input")
        XCTAssertTrue(caps.videoIn, "dense 31B supports video input")
        XCTAssertFalse(caps.imageOut)
    }

    func testGemma4_26BMoEVideoYesAudioNo() {
        let info = ModelInfo(
            id: "ollama:gemma-4:26b",
            rawName: "gemma-4:26b",
            displayName: "Gemma 4 · 26B MoE",
            runtimeId: "ollama",
            family: "gemma-4",
            variant: "26b"
        )
        let caps = CapabilityMap.capabilities(for: info)
        XCTAssertFalse(caps.audioIn)
        XCTAssertTrue(caps.videoIn)
    }

    // MARK: - Fallbacks

    func testUnknownVariantFallsBackToFamilyDefault() {
        let info = ModelInfo(
            id: "ollama:gemma-4:9b-wild",
            rawName: "gemma-4:9b-wild",
            displayName: "Gemma 4 · 9B-Wild",
            runtimeId: "ollama",
            family: "gemma-4",
            variant: "9b-wild"
        )
        let caps = CapabilityMap.capabilities(for: info)
        XCTAssertTrue(caps.textIn)
        XCTAssertTrue(caps.imageIn)
        XCTAssertEqual(caps.contextTokens, 128_000, "family fallback should pin to 128k")
    }

    func testCompletelyUnknownFamilyKeepsInputCapabilities() {
        let info = ModelInfo(
            id: "ollama:exotic-llm:1b",
            rawName: "exotic-llm:1b",
            displayName: "Exotic 1B",
            runtimeId: "ollama",
            family: "exotic-llm",
            variant: "1b",
            capabilities: .textOnly
        )
        let caps = CapabilityMap.capabilities(for: info)
        XCTAssertEqual(caps, .textOnly)
    }

    // MARK: - Upgrade

    func testUpgradeReplacesCapabilitiesButPreservesEverythingElse() {
        let info = ModelInfo(
            id: "ollama:gemma-4:e4b",
            rawName: "gemma-4:e4b",
            displayName: "Gemma 4 · E4B",
            runtimeId: "ollama",
            family: "gemma-4",
            variant: "e4b",
            sizeBytes: 4_500_000_000,
            isLoaded: true,
            capabilities: .textOnly
        )
        let upgraded = CapabilityMap.upgrade(info)
        XCTAssertEqual(upgraded.id, info.id)
        XCTAssertEqual(upgraded.sizeBytes, 4_500_000_000)
        XCTAssertTrue(upgraded.isLoaded)
        XCTAssertTrue(upgraded.capabilities.imageIn, "imageIn should now be true post-upgrade")
    }

    // MARK: - Diffusion models for Create-image gating

    func testDiffusionModelsEmitImages() {
        for family in ["flux", "sdxl", "stable-diffusion"] {
            let info = ModelInfo(
                id: "ollama:\(family)",
                rawName: family,
                displayName: family,
                runtimeId: "ollama",
                family: family
            )
            let caps = CapabilityMap.capabilities(for: info)
            XCTAssertTrue(caps.imageOut, "\(family) should report imageOut")
            XCTAssertFalse(caps.textOut)
            XCTAssertTrue(caps.tags.contains("image-gen"))
        }
    }
}
