import SwiftUI
import UIKitOmega

@main
struct LLMABApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 640)
                .task { await store.refresh() }
        }
    }
}
