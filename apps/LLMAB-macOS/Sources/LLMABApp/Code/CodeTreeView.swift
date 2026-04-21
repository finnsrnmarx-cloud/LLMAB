import SwiftUI
import UIKitOmega

/// Left-side file tree for the Code tab. Recursive, lazy-loaded, monospace,
/// cooler sub-palette. The recursive row is factored into a dedicated struct
/// (`CodeTreeRow`) so SwiftUI can resolve the opaque `some View` return type.
struct CodeTreeView: View {
    @ObservedObject var vm: CodeTabViewModel

    var body: some View {
        if vm.root == nil {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let root = vm.root {
                        rootHeader(root: root)
                    }
                    ForEach(vm.treeChildren) { node in
                        CodeTreeRow(vm: vm, node: node, depth: 0)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("no folder open")
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(Midnight.mist)
            Text("choose a folder from the right to begin bug-fix / refactor analysis.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Midnight.fog)
        }
        .padding(16)
    }

    private func rootHeader(root: URL) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(AuroraGradient.linear(.code))
            Text(root.lastPathComponent)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(Midnight.mist)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// One row in the tree. Recursion is through the struct type itself, which
/// SwiftUI can resolve cleanly.
struct CodeTreeRow: View {
    @ObservedObject var vm: CodeTabViewModel
    let node: CodeTreeNode
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowButton
            if node.isDirectory, vm.expanded.contains(node.url) {
                ForEach(vm.children(of: node)) { child in
                    CodeTreeRow(vm: vm, node: child, depth: depth + 1)
                }
            }
        }
    }

    private var rowButton: some View {
        let isSelected = vm.selectedFile == node.url
        let indent = CGFloat(depth) * 14 + 12
        return Button {
            if node.isDirectory {
                vm.toggleExpansion(node)
            } else {
                vm.selectFile(node.url)
            }
        } label: {
            HStack(spacing: 6) {
                if node.isDirectory {
                    Image(systemName: vm.expanded.contains(node.url)
                          ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Midnight.fog)
                        .frame(width: 10)
                } else {
                    Spacer().frame(width: 10)
                }
                Image(systemName: icon(for: node))
                    .font(.system(size: 11))
                    .foregroundStyle(
                        node.isDirectory
                        ? AnyShapeStyle(AuroraGradient.linear(.code))
                        : AnyShapeStyle(Midnight.fog)
                    )
                Text(node.name)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isSelected ? Midnight.mist : Midnight.fog)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.leading, indent)
            .padding(.trailing, 12)
            .background(
                isSelected
                ? AnyShapeStyle(Midnight.indigoDeep)
                : AnyShapeStyle(Color.clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(AuroraGradient.linear(.code))
                        .frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func icon(for node: CodeTreeNode) -> String {
        if node.isDirectory { return "folder" }
        switch node.ext {
        case "swift":                  return "swift"
        case "md", "markdown":         return "doc.text"
        case "json", "yml", "yaml":    return "curlybraces.square"
        case "sh", "bash", "zsh":      return "terminal"
        case "py":                     return "p.circle"
        case "js", "ts", "jsx", "tsx": return "j.circle"
        default:                       return "doc"
        }
    }
}
