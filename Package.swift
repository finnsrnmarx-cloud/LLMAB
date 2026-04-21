// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LLMAB",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "LLMCore", targets: ["LLMCore"]),
        .library(name: "RuntimeOllama", targets: ["RuntimeOllama"]),
        .library(name: "RuntimeMLX", targets: ["RuntimeMLX"]),
        .library(name: "RuntimeLlamaCpp", targets: ["RuntimeLlamaCpp"]),
        .library(name: "ModelRegistry", targets: ["ModelRegistry"]),
        .library(name: "AgentKit", targets: ["AgentKit"]),
        .library(name: "MediaKit", targets: ["MediaKit"]),
        .library(name: "UIKitOmega", targets: ["UIKitOmega"]),
        .executable(name: "llmab", targets: ["llmab"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "LLMCore",
            path: "packages/LLMCore/Sources/LLMCore"
        ),
        .testTarget(
            name: "LLMCoreTests",
            dependencies: ["LLMCore"],
            path: "packages/LLMCore/Tests/LLMCoreTests"
        ),
        .target(
            name: "RuntimeOllama",
            dependencies: ["LLMCore"],
            path: "packages/RuntimeOllama/Sources/RuntimeOllama"
        ),
        .target(
            name: "RuntimeMLX",
            dependencies: ["LLMCore"],
            path: "packages/RuntimeMLX/Sources/RuntimeMLX"
        ),
        .target(
            name: "RuntimeLlamaCpp",
            dependencies: ["LLMCore"],
            path: "packages/RuntimeLlamaCpp/Sources/RuntimeLlamaCpp"
        ),
        .target(
            name: "ModelRegistry",
            dependencies: ["LLMCore", "RuntimeOllama", "RuntimeMLX", "RuntimeLlamaCpp"],
            path: "packages/ModelRegistry/Sources/ModelRegistry"
        ),
        .target(
            name: "AgentKit",
            dependencies: ["LLMCore"],
            path: "packages/AgentKit/Sources/AgentKit"
        ),
        .target(
            name: "MediaKit",
            dependencies: ["LLMCore"],
            path: "packages/MediaKit/Sources/MediaKit"
        ),
        .target(
            name: "UIKitOmega",
            path: "packages/UIKitOmega/Sources/UIKitOmega"
        ),
        .executableTarget(
            name: "llmab",
            dependencies: [
                "LLMCore",
                "ModelRegistry",
                "RuntimeOllama",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "cli/llmab/Sources/llmab"
        )
    ]
)
