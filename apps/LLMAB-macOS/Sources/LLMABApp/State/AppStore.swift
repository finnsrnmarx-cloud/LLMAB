import Foundation
import LLMCore
import ModelRegistry
import RuntimeLlamaCpp
import SwiftUI

/// App-wide shared state: the registry, the snapshot, the chosen model, and —
/// critically for cross-tab memory — the long-lived view-models for Chat,
/// Code, and Agents. Video intentionally keeps its VM local to the tab
/// because the live camera session must restart with the view anyway.
///
/// Each long-lived VM persists its state via `PersistenceStore` so tab
/// switches, app relaunches, and even crashes don't blow away the
/// conversation.
@MainActor
final class AppStore: ObservableObject {

    let registry: ModelRegistry
    let persistence: PersistenceStore
    /// Manages a spawned llama-server subprocess so the user can pick a
    /// GGUF from the Settings pane and hit "start" without opening a
    /// terminal. See `LlamaServerController` for lifecycle + readiness
    /// polling details.
    let llamaServer = LlamaServerController()

    @Published private(set) var snapshot: ModelRegistry.Snapshot?
    @Published private(set) var isScanning: Bool = false
    @Published var selectedModelId: String? {
        didSet {
            guard oldValue != selectedModelId else { return }
            var s = persistedSettings
            s.selectedModelId = selectedModelId
            persistedSettings = s
            persistence.save(s, forKey: PersistenceKeys.settings)
        }
    }
    @Published var ttsVoiceIdentifier: String? {
        didSet {
            guard oldValue != ttsVoiceIdentifier else { return }
            var s = persistedSettings
            s.ttsVoiceIdentifier = ttsVoiceIdentifier
            persistedSettings = s
            persistence.save(s, forKey: PersistenceKeys.settings)
        }
    }

    /// Long-lived view-models, constructed once and handed out via
    /// EnvironmentObject so every tab reuses the same instance.
    let chatVM: ChatViewModel
    let codeVM: CodeTabViewModel
    let agentsVM: AgentsTabViewModel

    /// Cached copy of the Settings payload so we don't lose unchanged fields
    /// when persisting a single update.
    private var persistedSettings: SettingsPersistedState

    init(registry: ModelRegistry = ModelRegistry(),
         persistence: PersistenceStore = .shared) {
        self.registry = registry
        self.persistence = persistence

        // Rehydrate settings before building VMs — selectedModelId needs to
        // be set before the Chat VM starts streaming, otherwise autoPick
        // will overwrite it.
        let settings = persistence.load(SettingsPersistedState.self,
                                        forKey: PersistenceKeys.settings)
            ?? SettingsPersistedState()
        self.persistedSettings = settings
        self.selectedModelId = settings.selectedModelId
        self.ttsVoiceIdentifier = settings.ttsVoiceIdentifier

        // Construct VMs with their persisted state.
        self.chatVM   = ChatViewModel(persistence: persistence)
        self.codeVM   = CodeTabViewModel(persistence: persistence)
        self.agentsVM = AgentsTabViewModel(persistence: persistence)

        // Wire VMs to this store so they can look up the selected model.
        self.chatVM.bind(to: self)
        self.codeVM.bind(to: self)
        self.agentsVM.bind(to: self)

        // Seed the local GGUF scan so Settings shows the picker immediately.
        self.llamaServer.rescanLocal()
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

    /// Force-flush every VM's state to disk. Call from `applicationWillTerminate`
    /// or similar teardown points to ensure no in-flight debounces drop.
    func flushPersistence() {
        // Kill any spawned llama-server first so it doesn't orphan when the
        // app quits.
        llamaServer.stop()
        chatVM.flushPersistence()
        codeVM.flushPersistence()
        agentsVM.flushPersistence()
        persistence.saveNow(persistedSettings, forKey: PersistenceKeys.settings)
    }
}
