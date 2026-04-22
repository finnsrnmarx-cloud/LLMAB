import SwiftUI
import UIKitOmega

/// Settings lives both as a left-rail tab (for reach without ⌘,) and as the
/// SwiftUI `Settings` scene (⌘, opens a separate window). Both surfaces reuse
/// the same `SettingsView` body, so the three sections (runtimes, models,
/// pull, voice) stay in sync no matter how the user got there.
struct SettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("Settings",
                      subtitle: "runtimes · models · pull · voice",
                      palette: .full,
                      showSpinner: false)
            SettingsView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
