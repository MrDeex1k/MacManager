import AppKit
import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Group {
            if state.mainWindowVisible {
                content(state: state)
            } else {
                Color.clear
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMainWindowRequested)) { _ in
            state.setMainWindowVisible(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard isMainWindow(notification.object) else { return }
            state.mainWindowWillClose()
        }
    }

    private func content(state source: AppState) -> some View {
        @Bindable var state = source
        return NavigationSplitView {
            List(AppSection.allCases, selection: $state.section) { section in
                NavigationLink(value: section) {
                    Label(state.strings(section.titleKey), systemImage: section.symbol)
                        .padding(.vertical, 5)
                }
                .accessibilityIdentifier("navigation.\(section.rawValue)")
            }
            .listStyle(.sidebar)
            .navigationTitle("Mac Manager")
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
            .safeAreaInset(edge: .bottom) {
                Label(state.strings("app.name"), systemImage: "macbook")
                    .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        } detail: {
            ScrollView {
                Group {
                    switch state.section ?? .overview {
                    case .overview: OverviewView()
                    case .sensors: SensorsView()
                    case .network: NetworkView()
                    case .scroll: ScrollSettingsView()
                    case .dock: DockSettingsView()
                    case .settings: SettingsView()
                    }
                }
                .padding(32)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("main.detailScroll")
            .background(AppTheme.canvas)
            .navigationTitle(state.strings((state.section ?? .overview).titleKey))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        state.section = .settings
                    } label: {
                        Label(state.strings("nav.settings"), systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("toolbar.settings")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func isMainWindow(_ object: Any?) -> Bool {
        guard let window = object as? NSWindow else { return false }
        return window.canBecomeMain && window.styleMask.contains(.titled) && window.level == .normal
    }
}
