import SwiftUI
import UIKitOmega

@main
struct LLMABApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 640)
        }
    }
}
