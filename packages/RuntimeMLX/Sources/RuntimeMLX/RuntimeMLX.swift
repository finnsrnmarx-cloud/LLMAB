import Foundation
import LLMCore

public enum RuntimeMLX {
    public static let id = "mlx"
}

/// LLMRuntime backed by the `mlx_lm` Python CLI (shelled-out). v1 discovery
/// scans `~/.cache/huggingface/hub/models--mlx-community--*` for locally
/// downloaded MLX-format models; chat invokes `mlx_lm.generate` as a
/// subprocess. Not streaming for v1 — we emit the full response as a single
/// `.text(...)` followed by `.finish(.stop, nil)`.
///
/// Longer-term we'd integrate the mlx-swift package directly for native
/// streaming; that's deferred until the Swift port stabilises.
public final class MLXRuntime: LLMRuntime, @unchecked Sendable {

    public let id = RuntimeMLX.id
    public let displayName = "MLX · Apple Silicon native"

    private let mlxBinary: URL?
    private let cacheRoot: URL

    public init(mlxBinary: URL? = Self.findMLXBinary(),
                cacheRoot: URL = Self.defaultCacheRoot()) {
        self.mlxBinary = mlxBinary
        self.cacheRoot = cacheRoot
    }

    // MARK: - Availability

    public func isAvailable() async -> Bool {
        mlxBinary != nil
    }

    // MARK: - Discovery

    public func discoverModels() async throws -> [ModelInfo] {
        let hubRoot = cacheRoot.appendingPathComponent("hub")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: hubRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        let mlxDirs = entries.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("models--mlx-community--")
        }
        return mlxDirs.map { dir in
            let raw = String(dir.lastPathComponent.dropFirst("models--".count))
                .replacingOccurrences(of: "--", with: "/")
            let sizeBytes = try? FileManager.default
                .attributesOfItem(atPath: dir.path)[.size] as? Int64
            let (family, variant) = Self.parseFamily(from: raw.lowercased())
            return ModelInfo(
                id: "\(RuntimeMLX.id):\(raw)",
                rawName: raw,
                displayName: Self.humanize(raw),
                runtimeId: RuntimeMLX.id,
                family: family,
                variant: variant,
                sizeBytes: sizeBytes
            )
        }
    }

    // MARK: - Chat (non-streaming, subprocess)

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream<ChatChunk, Error> { continuation in
            let task = Task {
                do {
                    try await self.runSubprocess(request: request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runSubprocess(request: ChatRequest,
                               continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) async throws {
        guard let bin = mlxBinary else {
            throw LLMRuntimeError.unavailable("mlx_lm binary not found on PATH")
        }

        #if !os(iOS) && !os(tvOS) && !os(watchOS)
        let modelName = request.modelId.hasPrefix("\(RuntimeMLX.id):")
            ? String(request.modelId.dropFirst(RuntimeMLX.id.count + 1))
            : request.modelId

        let prompt = request.messages.map { msg -> String in
            "\(msg.role.rawValue): \(msg.textContent)"
        }.joined(separator: "\n")

        let output = try await runProcess(
            executable: bin,
            arguments: [
                "--model", modelName,
                "--prompt", prompt,
                "--max-tokens", String(request.sampling.maxTokens ?? 2048)
            ]
        )
        continuation.yield(.text(output))
        continuation.yield(.finish(reason: .stop, usage: nil))
        continuation.finish()
        #else
        throw LLMRuntimeError.unsupported("mlx_lm shell-out only on macOS hosts")
        #endif
    }

    #if !os(iOS) && !os(tvOS) && !os(watchOS)
    private func runProcess(executable: URL, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do { try process.run() }
            catch { cont.resume(throwing: error) }
        }
    }
    #endif

    // MARK: - Discovery helpers

    static func parseFamily(from id: String) -> (family: String, variant: String?) {
        if id.contains("gemma-4") { return ("gemma-4", firstMatching(id, of: ["e2b", "e4b", "26b", "31b"])) }
        if id.contains("gemma-3") { return ("gemma-3", firstMatching(id, of: ["2b", "7b", "27b"])) }
        if id.contains("llama-3") { return ("llama-3", firstMatching(id, of: ["8b", "70b"])) }
        return (id.split(separator: "/").first.map(String.init) ?? id, nil)
    }

    private static func firstMatching(_ id: String, of tokens: [String]) -> String? {
        tokens.first(where: { id.contains($0) })
    }

    static func humanize(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    // MARK: - Platform helpers

    public static func findMLXBinary() -> URL? {
        #if !os(iOS) && !os(tvOS) && !os(watchOS)
        let paths = ["/opt/homebrew/bin/mlx_lm", "/usr/local/bin/mlx_lm"]
        for p in paths where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        // Try PATH lookup via `which`.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["mlx_lm"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : URL(fileURLWithPath: out)
        #else
        return nil
        #endif
    }

    public static func defaultCacheRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/huggingface")
    }
}
