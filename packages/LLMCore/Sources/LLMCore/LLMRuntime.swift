import Foundation

/// A single model provider: local runtimes such as the Ollama daemon,
/// `mlx_lm`, `llama-server`, plus opt-in cloud providers.
///
/// Implementations are expected to be `Sendable`, since the UI and the
/// `ModelRegistry` call them from arbitrary tasks.
public protocol LLMRuntime: Sendable {

    /// Stable identifier: "ollama", "mlx", "llamacpp", "deepseek". Matches
    /// `ModelInfo.runtimeId`.
    var id: String { get }

    /// User-facing label for Settings ("Ollama · local daemon").
    var displayName: String { get }

    /// Cheap probe — is this runtime installed / reachable on this machine?
    /// Used by `ModelRegistry.scan()` to skip absent runtimes without blowing
    /// up the Settings pane.
    func isAvailable() async -> Bool

    /// List every model this runtime currently has locally. The registry then
    /// merges this into a single capability-annotated list.
    func discoverModels() async throws -> [ModelInfo]

    /// Pull / download a model by raw name, emitting progress events. Not every
    /// runtime supports this; the default returns an `unsupported` error.
    func pullModel(_ rawName: String) -> AsyncThrowingStream<PullProgress, Error>

    /// Run a chat completion. The stream yields `ChatChunk` events and
    /// terminates with a `.finish`.
    func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error>
}

public extension LLMRuntime {
    func pullModel(_ rawName: String) -> AsyncThrowingStream<PullProgress, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMRuntimeError.unsupported("pull not supported by runtime \(id)"))
        }
    }
}

/// Progress event emitted during a model download.
public struct PullProgress: Sendable, Hashable, Codable {
    public var status: String            // human-readable status
    public var downloadedBytes: Int64?
    public var totalBytes: Int64?
    public var digest: String?
    public var completed: Bool

    public init(status: String,
                downloadedBytes: Int64? = nil,
                totalBytes: Int64? = nil,
                digest: String? = nil,
                completed: Bool = false) {
        self.status = status
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.digest = digest
        self.completed = completed
    }

    public var fraction: Double? {
        guard let total = totalBytes, total > 0, let done = downloadedBytes else { return nil }
        return min(1.0, max(0.0, Double(done) / Double(total)))
    }
}

public enum LLMRuntimeError: Error, Sendable, CustomStringConvertible {
    case unavailable(String)
    case unsupported(String)
    case badResponse(String)
    case http(status: Int, body: String)
    case decoding(Error)
    case cancelled

    public var description: String {
        switch self {
        case .unavailable(let s): "runtime unavailable: \(s)"
        case .unsupported(let s): "unsupported operation: \(s)"
        case .badResponse(let s): "bad response: \(s)"
        case .http(let status, let body): "http \(status): \(body)"
        case .decoding(let err): "decoding error: \(err)"
        case .cancelled: "cancelled"
        }
    }
}
