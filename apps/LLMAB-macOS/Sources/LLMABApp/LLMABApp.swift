import SwiftUI
import MediaKit
import UIKitOmega

@main
struct LLMABApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var tts = TTSService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(tts)
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 640)
                .task { await store.refresh() }
        }
    }
}
