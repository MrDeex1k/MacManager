import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
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
                VStack(alignment: .leading, spacing: 5) {
                    Label("Mac Manager", systemImage: "macbook")
                        .font(.callout.weight(.semibold))
                    Text(state.strings("sidebar.private"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        } detail: {
            ScrollView {
                Group {
                    switch state.section ?? .overview {
                    case .overview: OverviewView()
                    case .network: NetworkView()
                    case .settings: SettingsView()
                    }
                }
                .padding(32)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
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
}
