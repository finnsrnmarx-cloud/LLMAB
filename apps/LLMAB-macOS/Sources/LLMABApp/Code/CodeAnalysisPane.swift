import SwiftUI
import UIKitOmega

/// Right-side analysis pane for the Code tab. Streams bug-fix / refactor /
/// summary text from the selected model; header carries the filename and a
/// spinning ω while streaming.
struct CodeAnalysisPane: View {
    @ObservedObject var vm: CodeTabViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AuroraGradient.linear(.code).opacity(0.25))
            body(for: vm.selectedFile)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if let file = vm.selectedFile {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraGradient.linear(.code))
                Text(file.lastPathComponent)
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Midnight.mist)
                    .lineLimit(1)
            } else {
                Text("select a file in the tree")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Midnight.fog)
            }
            Spacer()
            if vm.isAnalyzing {
                OmegaSpinner(size: 14, palette: .code)
            } else if vm.selectedFile != nil && vm.analysis.isEmpty {
                Button {
                    vm.runAnalysis()
                } label: {
                    HStack(spacing: 4) {
                        Text("analyze")
                            .font(.system(.caption2, design: .monospaced))
                        Image(systemName: "return")
                            .font(.system(size: 9))
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for file: URL?) -> some View {
        if let error = vm.error {
            errorView(error)
        } else if file == nil {
            emptyState
        } else if vm.analysis.isEmpty && !vm.isAnalyzing {
            hintView
        } else {
            ScrollView {
                Text(vm.analysis)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Midnight.mist)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                OmegaMark(size: 18, animated: true, palette: .code)
                Text("pick a file")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Midnight.mist)
            }
            Text("Click any file in the tree to load it. ω reads up to 64 KB per file and streams bug-fix, refactor, and summary notes below.")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Midnight.fog)
        }
        .padding(24)
    }

    private var hintView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ready")
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(Midnight.mist)
            Text("Press \"analyze\" above, or type a specific question in the prompt below.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Midnight.fog)
        }
        .padding(20)
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            AuroraRing(size: 16, lineWidth: 2, state: .failure)
            Text(message)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Midnight.mist)
        }
        .padding(20)
    }
}
