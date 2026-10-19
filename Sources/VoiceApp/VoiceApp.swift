import SwiftUI
import AppKit

@main
struct TVLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = EpisodeModel()
    @StateObject private var forwarder = InputForwarder()
    @StateObject private var discovery = ServerDiscovery()

    var body: some Scene {
        WindowGroup("TV Launcher") {
            ContentView()
                .environmentObject(model)
                .environmentObject(forwarder)
                .environmentObject(discovery)
                .onAppear { discovery.start() }
                .frame(minWidth: 820, idealWidth: 1000, minHeight: 560, idealHeight: 720)
        }
        .windowToolbarStyle(.unified)
        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(discovery)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
