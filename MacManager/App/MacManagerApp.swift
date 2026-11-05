import AppKit
import SwiftUI

extension Notification.Name {
    static let openMainWindowRequested = Notification.Name("dev.macmanager.open-main-window")
}

#if !MM_UNIT_TESTS
@main
struct MacManagerApp: App {
    @NSApplicationDelegateAdaptor(AppearanceDelegate.self) private var delegate
    @State private var state = AppState()

    var body: some Scene {
        Window("Mac Manager", id: "main") {
            AppShellView()
                .environment(state)
                .environment(\.locale, state.preferences.locale)
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultLaunchBehavior(state.launchContext == .loginItem ? .suppressed : .presented)
        .restorationBehavior(.disabled)
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

#endif

final class AppearanceDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        NotificationCenter.default.post(name: .openMainWindowRequested, object: nil)
        if let mainWindow = sender.windows.first(where: {
            $0.canBecomeMain && $0.styleMask.contains(.titled) && $0.level == .normal
        }) {
            mainWindow.makeKeyAndOrderFront(nil)
            sender.activate()
        }
        return true
    }

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
            Button(state.strings("launcher.open")) { state.launcher.show() }
                .accessibilityIdentifier("launcher.menu")
            Button(state.strings("island.open")) { state.island.showFromKeyboard() }
                .disabled(!state.preferences.island.enabled)
                .accessibilityIdentifier("island.menu")
            #if DEBUG
            if UITestConfiguration.current.contains("--ui-testing") {
                Button("Suspend Island Session") { state.island.setSessionSuspendedForTesting(true) }
                Button("Resume Island Session") { state.island.setSessionSuspendedForTesting(false) }
                Button("Simulate Constrained Display") { state.launcher.simulateDisplayChangeForTesting("constrained") }
                Button("Simulate Display Removal") { state.launcher.simulateDisplayChangeForTesting("removed") }
                Button("Simulate No Displays") { state.launcher.simulateDisplayChangeForTesting("none") }
                Button("Restore Display Metadata") { state.launcher.simulateDisplayChangeForTesting("restore") }
                Button("Simulate Panel Sleep") { SystemSessionMonitor.shared.setSleepingForTesting(true) }
                Button("Simulate Panel Wake") { SystemSessionMonitor.shared.setSleepingForTesting(false) }
                #if MM_RESERVED_REGION_PROBE
                if UITestConfiguration.current.contains("--island-reserved-region-probe") {
                    Button("Probe Island on External Display") { state.island.selectProbeDisplayForTesting(external: true) }
                    Button("Probe Island on Built-in Display") { state.island.selectProbeDisplayForTesting(external: false) }
                }
                #endif
            }
            #endif
            Button(state.strings("nav.overview")) { navigate(.overview) }
                .keyboardShortcut("1", modifiers: .command)
            Button(state.strings("nav.network")) { navigate(.network) }
                .keyboardShortcut("2", modifiers: .command)
        }
    }

    private func navigate(_ section: AppSection) {
        state.section = section
        state.setMainWindowVisible(true)
        openWindow(id: "main")
        NSApp.activate()
    }
}
