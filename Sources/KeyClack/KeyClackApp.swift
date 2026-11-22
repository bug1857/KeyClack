import SwiftUI
import AppKit
import KeyClackCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run purely as a menu bar utility (no Dock icon, no app switcher entry)
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct KeyClackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
        } label: {
            Image(systemName: appState.isActivelyPlaying ? "keyboard" : "speaker.slash")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
