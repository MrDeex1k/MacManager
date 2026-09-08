import AppKit
import SwiftUI

@main
struct MacManagerApp: App {
    @NSApplicationDelegateAdaptor(AppearanceDelegate.self) private var delegate
    @State private var state = AppState()

    var body: some Scene {
        Window("Mac Manager", id: "main") {
            MainWindowContent(state: state)
                .environment(\.locale, state.preferences.locale)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultLaunchBehavior(state.launchContext == .loginItem ? .suppressed : .presented)
        .defaultSize(width: 1080, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            AppCommands(state: state)
        }

        MenuBarExtra {
            MenuBarPanelView()
                .environment(state)
        } label: {
            MenuBarLabelView(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppearanceDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        if let mainWindow = sender.windows.first(where: { $0.title == "Mac Manager" && $0.canBecomeMain }) {
            mainWindow.makeKeyAndOrderFront(nil)
            sender.activate()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

private struct MainWindowContent: View {
    let state: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        AppShellView()
            .environment(state)
            .task {
                guard state.consumeInitialLoginWindowSuppression() else { return }
                await Task.yield()
                dismissWindow(id: "main")
            }
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
