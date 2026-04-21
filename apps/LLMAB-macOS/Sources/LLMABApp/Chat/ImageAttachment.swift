import Foundation

/// A pending image attachment queued for the next send. The data is raw
/// (already-encoded PNG/JPEG bytes) ready for `ContentPart.image(_:mimeType:)`.
struct ImageAttachment: Identifiable, Hashable {
    let id: UUID
    let data: Data
    let mimeType: String
    let filename: String?

    init(id: UUID = UUID(), data: Data, mimeType: String, filename: String? = nil) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
        self.filename = filename
    }

    /// Short label shown on the attachment chip.
    var shortLabel: String {
        if let filename { return filename }
        let kb = max(1, data.count / 1024)
        return "image · \(kb) KB"
    }
}
