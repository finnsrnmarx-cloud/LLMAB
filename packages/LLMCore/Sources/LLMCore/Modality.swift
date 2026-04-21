import Foundation

/// The four I/O modalities LLMAB cares about. Each `ModelCapabilities` records
/// which of these a given model can *consume* (input) and *emit* (output).
public enum Modality: String, Sendable, CaseIterable, Codable {
    case text
    case image
    case audio
    case video
}
