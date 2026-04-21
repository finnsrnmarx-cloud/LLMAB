import Foundation
import LLMCore

/// Namespace + default endpoint. `OllamaRuntime` is the actual `LLMRuntime`
/// implementation.
public enum RuntimeOllama {
    public static let id = "ollama"
    public static let defaultEndpoint = URL(string: "http://127.0.0.1:11434")!
}
