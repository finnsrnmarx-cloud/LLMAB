import SwiftUI
import UIKitOmega

/// Code tab — top-left in the rail per spec. Uses the cooler sub-palette
/// (cyan → teal → indigo → violet) and monospace everything. Real folder
/// picker + file tree + analysis pane ships in chunk 11.
struct CodeTab: View {
    @State private var commandText: String = ""
    @State private var isAnalyzing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TabHeader("Code",
                      subtitle: "cli · aurora-code",
                      palette: .code)

            PlaceholderCard(
                title: "Ships in chunk 11",
                message: "Security-scoped folder picker → aurora-striped file tree → streaming bug-fix / refactor / summary panel. \"Apply suggestion\" writes via the bookmark, never via a sandboxed daemon.",
                palette: .code
            )

            Spacer(minLength: 0)

            CLIPrompt(
                text: $commandText,
                isWorking: isAnalyzing,
                placeholder: "analyze file or ask about the codebase"
            ) {
                // chunk 11 will route this through the chosen model
                commandText = ""
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
