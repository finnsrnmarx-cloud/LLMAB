import SwiftUI
import UIKitOmega
import UniformTypeIdentifiers

/// Code tab — top-left in the rail per spec. Left: lazy file tree. Right:
/// streaming bug-fix/refactor analysis. Bottom: CLIPrompt for freeform
/// questions about the selected file. Cooler sub-palette (cyan → teal →
/// indigo → violet), monospace.
struct CodeTab: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        CodeTabContent(vm: store.codeVM)
    }
}

/// Inner view observes the shared CodeTabViewModel so SwiftUI re-renders on
/// tree expansion / selection / analysis streaming. See AgentsTab for the
/// same rationale.
private struct CodeTabContent: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var vm: CodeTabViewModel
    @State private var isPickingFolder: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("Code",
                      subtitle: subtitle,
                      palette: .code,
                      showSpinner: vm.isAnalyzing)

            HStack(spacing: 0) {
                treePanel
                    .frame(width: 260)
                    .background(Midnight.abyss)
                Divider().overlay(AuroraGradient.linear(.code).opacity(0.25))
                CodeAnalysisPane(vm: vm)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            Divider().overlay(AuroraGradient.linear(.code).opacity(0.25))

            CLIPrompt(
                text: $vm.input,
                isWorking: vm.isAnalyzing,
                placeholder: placeholder
            ) {
                vm.runAnalysis()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Midnight.indigoDeep)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // vm is bound in AppStore.init, nothing to do here.
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                vm.openFolder(url)
            }
        }
    }

    // MARK: - Sub-panels

    private var treePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    isPickingFolder = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11))
                        Text(vm.root == nil ? "open folder" : "change")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .foregroundStyle(Midnight.mist)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Midnight.indigoDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(AuroraGradient.linear(.code), lineWidth: 0.8)
                            .opacity(0.6)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider().overlay(AuroraGradient.linear(.code).opacity(0.2))
            CodeTreeView(vm: vm)
        }
    }

    // MARK: - Header bits

    private var subtitle: String {
        if let f = vm.selectedFile {
            return "cli · \(f.lastPathComponent)"
        }
        return "cli · aurora-code"
    }

    private var placeholder: String {
        if vm.selectedFile == nil { return "pick a file first" }
        return "ask about this file — or ↵ for default analysis"
    }
}
