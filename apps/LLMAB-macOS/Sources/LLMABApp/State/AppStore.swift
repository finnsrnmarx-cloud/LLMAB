import Foundation
import LLMCore
import ModelRegistry
import SwiftUI

/// App-wide shared state: the registry, the snapshot, and the chosen model.
/// Every tab's view-model reads the selected model from here.
@MainActor
final class AppStore: ObservableObject {

    let registry: ModelRegistry

    @Published private(set) var snapshot: ModelRegistry.Snapshot?
    @Published private(set) var isScanning: Bool = false
    @Published var selectedModelId: String?

    init(registry: ModelRegistry = ModelRegistry()) {
        self.registry = registry
    }

    /// Resolve the currently-selected model (runtime + info). Nil if nothing
    /// is selected or the selection doesn't match anything in the snapshot.
    var selected: (runtime: any LLMRuntime, info: ModelInfo)? {
        get async {
            guard let id = selectedModelId else { return nil }
            return await registry.resolve(modelId: id)
        }
    }

    /// Scan runtimes, refresh the snapshot, and auto-select a sane default if
    /// nothing is selected yet.
    func refresh() async {
        isScanning = true
        defer { isScanning = false }
        let snap = await registry.scan()
        snapshot = snap
        if selectedModelId == nil {
            selectedModelId = autoPick(snap: snap)
        }
    }

    /// Default-selection priority:
    ///   1. recommended tag (gemma-4:e4b)
    ///   2. any Gemma 4 variant, largest first
    ///   3. first model reported by any runtime
    private func autoPick(snap: ModelRegistry.Snapshot) -> String? {
        if let recommended = snap.models.first(where: { $0.capabilities.tags.contains("recommended") }) {
            return recommended.id
        }
        if let gemma = snap.models.first(where: { $0.family.hasPrefix("gemma-4") }) {
            return gemma.id
        }
        return snap.models.first?.id
    }
}
