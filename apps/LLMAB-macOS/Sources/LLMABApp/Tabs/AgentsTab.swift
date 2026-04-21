import SwiftUI
import UIKitOmega

/// Agents tab — tool-use loop with shell, file, web-search tools. Real
/// implementation ships in chunk 12.
struct AgentsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TabHeader("Agents",
                      subtitle: "tool-use · aurora-full",
                      palette: .full)

            PlaceholderCard(
                title: "Ships in chunk 12",
                message: "Tool loop: read_file, write_file, run_shell (allowlist + per-command consent), web_search (opt-in DuckDuckGo), list_dir. Uses Gemma 4's native function-calling and optional thinking mode. Every in-flight tool call shows its own AuroraRing beside the tool name.",
                palette: .full
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
