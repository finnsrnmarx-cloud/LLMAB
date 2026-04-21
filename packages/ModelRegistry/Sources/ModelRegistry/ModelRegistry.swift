import Foundation
import LLMCore
import RuntimeOllama

/// Central aggregator across every installed `LLMRuntime`. Scans them all in
/// parallel, merges the results, and upgrades each `ModelInfo` with the
/// accurate capability matrix from `CapabilityMap`.
public actor ModelRegistry {

    public struct Snapshot: Sendable {
        public var models: [ModelInfo]
        public var runtimes: [RuntimeStatus]
        public var scannedAt: Date

        public init(models: [ModelInfo], runtimes: [RuntimeStatus], scannedAt: Date = Date()) {
            self.models = models
            self.runtimes = runtimes
            self.scannedAt = scannedAt
        }

        /// Models whose capabilities include the given modality on input.
        public func models(accepting modality: Modality) -> [ModelInfo] {
            models.filter { $0.capabilities.accepts(modality) }
        }

        /// Models flagged with a particular tag (e.g. "recommended").
        public func models(tagged tag: String) -> [ModelInfo] {
            models.filter { $0.capabilities.tags.contains(tag) }
        }
    }

    public struct RuntimeStatus: Sendable, Identifiable {
        public var id: String
        public var displayName: String
        public var available: Bool
        public var modelCount: Int
        public var error: String?

        public init(id: String, displayName: String, available: Bool, modelCount: Int, error: String? = nil) {
            self.id = id
            self.displayName = displayName
            self.available = available
            self.modelCount = modelCount
            self.error = error
        }
    }

    // MARK: - State

    private let runtimes: [any LLMRuntime]
    private var lastSnapshot: Snapshot?

    public init(runtimes: [any LLMRuntime] = ModelRegistry.defaultRuntimes()) {
        self.runtimes = runtimes
    }

    /// Default set for v1. MLX and llama.cpp adapters slot in during chunk 14;
    /// this list grows to `[OllamaRuntime(), MLXRuntime(), LlamaCppRuntime()]`.
    public static func defaultRuntimes() -> [any LLMRuntime] {
        [OllamaRuntime()]
    }

    // MARK: - Scan

    /// Probe every runtime in parallel, discover its models, and cache the
    /// result. UI calls this on first launch, on Settings refresh, and after a
    /// model pull completes.
    @discardableResult
    public func scan() async -> Snapshot {
        var statuses: [RuntimeStatus] = []
        var allModels: [ModelInfo] = []

        await withTaskGroup(of: (RuntimeStatus, [ModelInfo]).self) { group in
            for runtime in runtimes {
                group.addTask {
                    let available = await runtime.isAvailable()
                    guard available else {
                        return (RuntimeStatus(
                            id: runtime.id,
                            displayName: runtime.displayName,
                            available: false,
                            modelCount: 0,
                            error: "runtime not reachable"
                        ), [])
                    }
                    do {
                        let raw = try await runtime.discoverModels()
                        let upgraded = raw.map(CapabilityMap.upgrade)
                        return (RuntimeStatus(
                            id: runtime.id,
                            displayName: runtime.displayName,
                            available: true,
                            modelCount: upgraded.count
                        ), upgraded)
                    } catch {
                        return (RuntimeStatus(
                            id: runtime.id,
                            displayName: runtime.displayName,
                            available: true,
                            modelCount: 0,
                            error: String(describing: error)
                        ), [])
                    }
                }
            }

            for await (status, models) in group {
                statuses.append(status)
                allModels.append(contentsOf: models)
            }
        }

        let snapshot = Snapshot(
            models: allModels.sorted(by: Self.sortKey),
            runtimes: statuses.sorted { $0.id < $1.id }
        )
        lastSnapshot = snapshot
        return snapshot
    }

    /// Non-blocking read of the most recent scan, if any.
    public func cached() -> Snapshot? { lastSnapshot }

    /// Look up a runtime adapter by id — used by the CLI's `chat`, the app's
    /// chat view, and the pull progress stream.
    public func runtime(id: String) -> (any LLMRuntime)? {
        runtimes.first(where: { $0.id == id })
    }

    /// Resolve a `ModelInfo.id` back to (runtime, info). Returns nil if the
    /// model vanished from the last scan (pulled then removed).
    public func resolve(modelId: String) -> (runtime: any LLMRuntime, info: ModelInfo)? {
        guard let snapshot = lastSnapshot,
              let info = snapshot.models.first(where: { $0.id == modelId }),
              let rt = runtime(id: info.runtimeId)
        else { return nil }
        return (rt, info)
    }

    // MARK: - Sorting

    /// Loaded first, then by runtime id, then by size descending, then name.
    private static func sortKey(_ a: ModelInfo, _ b: ModelInfo) -> Bool {
        if a.isLoaded != b.isLoaded { return a.isLoaded && !b.isLoaded }
        if a.runtimeId != b.runtimeId { return a.runtimeId < b.runtimeId }
        if (a.sizeBytes ?? 0) != (b.sizeBytes ?? 0) {
            return (a.sizeBytes ?? 0) > (b.sizeBytes ?? 0)
        }
        return a.displayName < b.displayName
    }
}
