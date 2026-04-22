import Foundation
import LLMCore

/// Reads and writes the app's durable state under
/// `~/Library/Application Support/LLMAB/`. Writes are debounced per key so a
/// chat that mutates on every token doesn't hit the disk every token.
///
/// Everything here is best-effort: a corrupt or missing file results in the
/// default value being returned, never a thrown error to the caller.
public final class PersistenceStore: @unchecked Sendable {

    public static let shared = PersistenceStore()

    private let root: URL
    private let io = DispatchQueue(label: "org.llmab.persistence", qos: .utility)
    private var pendingTimers: [String: DispatchSourceTimer] = [:]
    private let debounceInterval: TimeInterval

    public init(bundleId: String = "org.llmab.omega",
                debounceInterval: TimeInterval = 0.4) {
        self.debounceInterval = debounceInterval
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.root = base.appendingPathComponent(bundleId, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: self.root,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Public API

    /// Read `Codable` value synchronously. Returns `nil` if the file is
    /// missing, corrupt, or mismatched type.
    public func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Write `Codable` value asynchronously, debounced per key. Multiple calls
    /// with the same key within `debounceInterval` collapse into a single I/O.
    public func save<T: Encodable>(_ value: T, forKey key: String) {
        let url = fileURL(forKey: key)
        guard let data = try? JSONEncoder().encode(value) else { return }

        io.async { [weak self] in
            guard let self else { return }
            self.pendingTimers[key]?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.io)
            timer.schedule(deadline: .now() + self.debounceInterval)
            timer.setEventHandler { [weak self] in
                try? data.write(to: url, options: .atomic)
                self?.pendingTimers.removeValue(forKey: key)
            }
            timer.resume()
            self.pendingTimers[key] = timer
        }
    }

    /// Force an immediate write (bypasses debouncing). Used on app shutdown.
    public func saveNow<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let url = fileURL(forKey: key)
        io.sync {
            pendingTimers[key]?.cancel()
            pendingTimers.removeValue(forKey: key)
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Clear a key's persisted file.
    public func clear(key: String) {
        let url = fileURL(forKey: key)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Internals

    private func fileURL(forKey key: String) -> URL {
        root.appendingPathComponent("\(key).json")
    }
}

// MARK: - Persisted payload types

/// Top-level snapshot of a ChatViewModel's state — everything we care about
/// preserving across tab switches and app launches.
public struct ChatPersistedState: Codable, Sendable {
    public var turns: [Message]
    public var input: String

    public init(turns: [Message] = [], input: String = "") {
        self.turns = turns
        self.input = input
    }
}

/// Snapshot of an AgentsTabViewModel's transcript. Turn.Kind is flattened
/// into a tagged union that round-trips cleanly through JSON.
public struct AgentsPersistedState: Codable, Sendable {
    public var turns: [Entry]
    public var input: String
    public var enableWebSearch: Bool

    public struct Entry: Codable, Sendable {
        public var kind: String     // "assistant" | "toolCall" | "toolResult" | "toolError" | "note"
        public var text: String?
        public var toolId: String?
        public var argumentsJSON: Data?

        public init(kind: String, text: String? = nil, toolId: String? = nil, argumentsJSON: Data? = nil) {
            self.kind = kind
            self.text = text
            self.toolId = toolId
            self.argumentsJSON = argumentsJSON
        }
    }

    public init(turns: [Entry] = [], input: String = "", enableWebSearch: Bool = false) {
        self.turns = turns
        self.input = input
        self.enableWebSearch = enableWebSearch
    }
}

/// Minimal snapshot of the Code tab: the open folder and selected file.
public struct CodePersistedState: Codable, Sendable {
    public var rootPath: String?
    public var selectedFilePath: String?

    public init(rootPath: String? = nil, selectedFilePath: String? = nil) {
        self.rootPath = rootPath
        self.selectedFilePath = selectedFilePath
    }
}

/// Global settings.
public struct SettingsPersistedState: Codable, Sendable {
    public var selectedModelId: String?
    public var ttsVoiceIdentifier: String?

    public init(selectedModelId: String? = nil, ttsVoiceIdentifier: String? = nil) {
        self.selectedModelId = selectedModelId
        self.ttsVoiceIdentifier = ttsVoiceIdentifier
    }
}

public enum PersistenceKeys {
    public static let chat     = "chat"
    public static let agents   = "agents"
    public static let code     = "code"
    public static let settings = "settings"
}
