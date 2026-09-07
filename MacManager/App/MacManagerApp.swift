import AppKit
import SwiftUI

@main
struct MacManagerApp: App {
    @NSApplicationDelegateAdaptor(AppearanceDelegate.self) private var delegate
    @State private var state = AppState()

    var body: some Scene {
        Window("Mac Manager", id: "main") {
            AppShellView()
                .environment(state)
                .task { state.startServices() }
                .environment(\.locale, state.preferences.locale)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1080, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            AppCommands(state: state)
        }
    }
}

final class AppearanceDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

struct AppCommands: Commands {
    let state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(state.strings("nav.settings")) { navigate(.settings) }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            Button(state.strings("nav.overview")) { navigate(.overview) }
                .keyboardShortcut("1", modifiers: .command)
            Button(state.strings("nav.network")) { navigate(.network) }
                .keyboardShortcut("2", modifiers: .command)
        }
    }

    private func navigate(_ section: AppSection) {
        state.section = section
        openWindow(id: "main")
        NSApp.activate()
    }
}
