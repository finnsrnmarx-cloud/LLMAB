import SwiftUI
import AppKit
import MediaKit
import UIKitOmega

@main
struct LLMABApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var tts = TTSService()

    /// Forwards NSApplication's `applicationWillTerminate` into `store`, so
    /// any in-flight debounced persistence writes get flushed to disk
    /// before the process exits.
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(tts)
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 640)
                .task {
                    lifecycle.store = store
                    await store.refresh()
                }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(tts)
                .preferredColorScheme(.dark)
        }
    }
}

/// Tiny AppDelegate that flushes AppStore persistence on quit. Without this,
/// a ⌘Q within the 0.4 s debounce window could drop the last state write.
final class AppLifecycle: NSObject, NSApplicationDelegate {
    weak var store: AppStore?

    func applicationWillTerminate(_ notification: Notification) {
        store?.flushPersistence()
    }
}
