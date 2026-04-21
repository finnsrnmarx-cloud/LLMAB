import SwiftUI
import UIKitOmega

/// Cmd-, settings pane. Real model manager + capability badges + runtime
/// detection land in chunk 15.
struct SettingsPlaceholderView: View {
    var body: some View {
        ZStack {
            Midnight.midnight.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    OmegaMark(size: 28, animated: true)
                    Text("Settings")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Midnight.mist)
                }
                Text("Model manager, runtime detection, and capability badges ship in chunk 15.")
                    .font(.system(.body))
                    .foregroundStyle(Midnight.fog)
            }
            .padding(28)
        }
        .frame(width: 480, height: 320)
    }
}
