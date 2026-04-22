import Foundation

// MARK: - Discovered GGUF

/// A GGUF file found on the local filesystem.
public struct GGUFFile: Identifiable, Hashable, Sendable {
    public let id: URL
    public let url: URL
    public let name: String            // filename
    public let sizeBytes: Int64?
    /// Auto-detected `mmproj-*.gguf` sitting next to the weights file.
    public let companionMmproj: URL?

    /// Rough family hint from the filename ("gemma-4", "llama-3", …).
    public let familyHint: String?
    /// Quantisation hint ("Q4_K_M", "UD-Q4_K_XL", …).
    public let quantHint: String?

    public init(url: URL,
                sizeBytes: Int64? = nil,
                companionMmproj: URL? = nil) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.sizeBytes = sizeBytes
        self.companionMmproj = companionMmproj
        let lowered = url.lastPathComponent.lowercased()
        self.familyHint = GGUFFile.parseFamily(lowered)
        self.quantHint = GGUFFile.parseQuant(url.lastPathComponent)
    }

    private static func parseFamily(_ lowered: String) -> String? {
        if lowered.contains("gemma-4") { return "gemma-4" }
        if lowered.contains("gemma-3") { return "gemma-3" }
        if lowered.contains("llama-3") { return "llama-3" }
        if lowered.contains("qwen") { return "qwen" }
        if lowered.contains("mistral") { return "mistral" }
        return nil
    }

    private static func parseQuant(_ name: String) -> String? {
        // Scan for common quant tokens. Case-sensitive on the token core
        // so "Q4_K_M" matches but "QUICK" doesn't.
        let patterns = ["UD-Q8_K_XL", "UD-Q6_K_XL", "UD-Q5_K_XL", "UD-Q4_K_XL",
                        "UD-Q3_K_XL", "UD-Q2_K_XL", "UD-IQ3_XXS", "UD-IQ2_M",
                        "Q8_0", "Q6_K", "Q5_K_M", "Q5_K_S",
                        "Q4_K_M", "Q4_K_S", "Q4_1", "Q4_0",
                        "Q3_K_M", "Q3_K_S", "Q2_K",
                        "IQ4_NL", "IQ4_XS", "BF16", "F16", "F32"]
        for p in patterns where name.contains(p) { return p }
        return nil
    }

    /// Pretty display label for the picker UI.
    public var displayLabel: String {
        let family = familyHint?.uppercased() ?? "model"
        let quant = quantHint ?? "?"
        return "\(family) · \(quant)"
    }
}

// MARK: - GGUF scanner

public enum GGUFScanner {
    /// Locations scanned by default — the two directories 99% of users
    /// have GGUF files in.
    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("models"),
            home.appendingPathComponent(".cache/huggingface/hub")
        ]
    }

    /// Recursively walk `roots`, looking for `.gguf` files. mmproj files
    /// (filenames starting with `mmproj`) are excluded from the top-level
    /// list and instead linked as `companionMmproj` on sibling weights
    /// when found in the same directory.
    public static func scan(_ roots: [URL] = defaultRoots) -> [GGUFFile] {
        let fm = FileManager.default
        var weights: [URL] = []
        var mmprojByDir: [URL: URL] = [:]

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "gguf" else { continue }
                let name = url.lastPathComponent.lowercased()
                if name.hasPrefix("mmproj") {
                    // Prefer BF16 over F16 over F32 (smaller / more
                    // accurate trade-off for Metal inference).
                    let dir = url.deletingLastPathComponent()
                    if let existing = mmprojByDir[dir] {
                        if rankMmproj(url) < rankMmproj(existing) {
                            mmprojByDir[dir] = url
                        }
                    } else {
                        mmprojByDir[dir] = url
                    }
                } else {
                    weights.append(url)
                }
            }
        }

        return weights.compactMap { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map(Int64.init)
            let dir = url.deletingLastPathComponent()
            return GGUFFile(url: url,
                            sizeBytes: size,
                            companionMmproj: mmprojByDir[dir])
        }.sorted { $0.name < $1.name }
    }

    /// Lower rank = preferred. BF16 beats F16 beats F32 on Metal.
    private static func rankMmproj(_ url: URL) -> Int {
        let n = url.lastPathComponent.lowercased()
        if n.contains("bf16") { return 0 }
        if n.contains("f16")  { return 1 }
        if n.contains("f32")  { return 2 }
        return 3
    }
}
