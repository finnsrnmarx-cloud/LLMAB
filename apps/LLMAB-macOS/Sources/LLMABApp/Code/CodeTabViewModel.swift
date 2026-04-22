import Foundation
import LLMCore
import ModelRegistry
import SwiftUI

/// State for the Code tab: a rooted folder, a lazily-loaded file tree, the
/// currently-selected file, and a streaming analysis pane.
@MainActor
final class CodeTabViewModel: ObservableObject {

    @Published var root: URL? { didSet { schedulePersist() } }
    @Published var treeChildren: [CodeTreeNode] = []
    @Published var expanded: Set<URL> = []
    @Published var expandedChildren: [URL: [CodeTreeNode]] = [:]
    @Published var selectedFile: URL? { didSet { schedulePersist() } }
    @Published var analysis: String = ""
    @Published var isAnalyzing: Bool = false
    @Published var input: String = ""
    @Published var error: String?

    private weak var store: AppStore?
    private var streamingTask: Task<Void, Never>?
    private let persistence: PersistenceStore
    private var rehydrating: Bool = false

    /// Max bytes we'll read from a single file before truncating. Keeps huge
    /// files from blowing the context window.
    static let maxFileBytes: Int = 64 * 1024

    init(persistence: PersistenceStore = .shared) {
        self.persistence = persistence
        rehydrate()
    }

    func bind(to store: AppStore) { self.store = store }

    private func rehydrate() {
        guard let saved = persistence.load(CodePersistedState.self,
                                           forKey: PersistenceKeys.code) else {
            return
        }
        rehydrating = true
        defer { rehydrating = false }
        if let rp = saved.rootPath {
            let url = URL(fileURLWithPath: rp)
            if FileManager.default.fileExists(atPath: url.path) {
                root = url
                treeChildren = CodeTree.children(of: url)
            }
        }
        if let sp = saved.selectedFilePath {
            let url = URL(fileURLWithPath: sp)
            if FileManager.default.fileExists(atPath: url.path) {
                selectedFile = url
            }
        }
    }

    private func schedulePersist() {
        guard !rehydrating else { return }
        let payload = CodePersistedState(
            rootPath: root?.path,
            selectedFilePath: selectedFile?.path
        )
        persistence.save(payload, forKey: PersistenceKeys.code)
    }

    func flushPersistence() {
        let payload = CodePersistedState(
            rootPath: root?.path,
            selectedFilePath: selectedFile?.path
        )
        persistence.saveNow(payload, forKey: PersistenceKeys.code)
    }

    // MARK: - Folder management

    func openFolder(_ url: URL) {
        root = url
        treeChildren = CodeTree.children(of: url)
        selectedFile = nil
        analysis = ""
        expanded = []
        expandedChildren = [:]
        error = nil
    }

    func toggleExpansion(_ node: CodeTreeNode) {
        guard node.isDirectory else { return }
        if expanded.contains(node.url) {
            expanded.remove(node.url)
        } else {
            expanded.insert(node.url)
            if expandedChildren[node.url] == nil {
                expandedChildren[node.url] = CodeTree.children(of: node.url)
            }
        }
    }

    func children(of node: CodeTreeNode) -> [CodeTreeNode] {
        expandedChildren[node.url] ?? []
    }

    // MARK: - Analysis

    func selectFile(_ url: URL) {
        selectedFile = url
        analysis = ""
        error = nil
    }

    /// Run whichever of the three flows the user most recently asked for:
    /// (1) default analysis if a file is selected and input is empty, or
    /// (2) a freeform question about the selected file using `input` as the
    /// user prompt. The CLIPrompt at the bottom of the Code tab always
    /// submits through here.
    func runAnalysis() {
        guard !isAnalyzing else { return }
        cancel()
        analysis = ""
        error = nil

        guard let file = selectedFile else {
            error = "select a file first"
            return
        }
        let userPrompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""

        streamingTask = Task { [weak self] in
            await self?.performAnalysis(file: file, userPrompt: userPrompt)
        }
    }

    func cancel() {
        streamingTask?.cancel()
        streamingTask = nil
        isAnalyzing = false
    }

    // MARK: - Analysis internals

    private func performAnalysis(file: URL, userPrompt: String) async {
        guard let store else { return }
        guard let resolved = await store.selected else {
            error = "no model selected — open Settings (chunk 15)"
            return
        }
        let (runtime, info) = resolved
        guard info.capabilities.textOut else {
            error = "\(info.displayName) does not emit text"
            return
        }

        let fileData: Data
        do {
            fileData = try Data(contentsOf: file)
        } catch {
            self.error = "read failed: \(error.localizedDescription)"
            return
        }

        let truncated = fileData.count > Self.maxFileBytes
        let slice = truncated ? fileData.prefix(Self.maxFileBytes) : fileData
        let content = String(data: slice, encoding: .utf8)
            ?? "⚠️ binary file (not utf-8) — \(fileData.count) bytes"

        let system = Message.system("""
        You are ω, a code-review assistant running on-device. The user has opened \
        a local file and wants a concise review. Be specific and actionable: \
        identify bugs, suggest refactors, call out risky patterns, and highlight \
        anything that could be simplified. Quote line fragments when pointing at \
        specific issues. Do not hallucinate imports or APIs you can't see.
        """)
        let userText: String
        if userPrompt.isEmpty {
            userText = """
            File: \(file.lastPathComponent)\(truncated ? " (truncated to first \(Self.maxFileBytes) bytes)" : "")
            Path: \(file.path)

            Please review:
            - Bugs or correctness issues
            - Refactoring opportunities
            - A one-paragraph summary

            ```\(file.pathExtension)
            \(content)
            ```
            """
        } else {
            userText = """
            Question: \(userPrompt)

            File: \(file.lastPathComponent)\(truncated ? " (truncated)" : "")

            ```\(file.pathExtension)
            \(content)
            ```
            """
        }

        let request = ChatRequest(
            modelId: info.id,
            messages: [system, .user(userText)],
            sampling: .balanced,
            stream: true
        )

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            for try await chunk in runtime.chat(request) {
                if Task.isCancelled { return }
                switch chunk {
                case .text(let delta):
                    analysis += delta
                case .toolCall, .finish:
                    break
                }
            }
        } catch {
            self.error = String(describing: error)
        }
    }
}
