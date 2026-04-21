import Foundation

/// Lazily-expandable file-tree node. Directories start with `children == nil`
/// (meaning "not loaded yet") and get populated on first expansion so we
/// don't read the entire tree upfront on huge repos.
struct CodeTreeNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [CodeTreeNode]?

    init(url: URL) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        self.children = nil
    }

    /// File extension lowercased, for icon selection and mimetype hints.
    var ext: String { url.pathExtension.lowercased() }
}

enum CodeTree {
    /// Load the immediate children of a directory. Skips hidden entries and
    /// common noise (`.git`, `node_modules`, `.build`, `DerivedData`).
    static func children(of url: URL) -> [CodeTreeNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let ignored: Set<String> = [".git", "node_modules", ".build",
                                    "DerivedData", ".swiftpm", "Pods",
                                    ".next", "dist", "build"]
        return contents
            .filter { !ignored.contains($0.lastPathComponent) }
            .map(CodeTreeNode.init(url:))
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }
}
