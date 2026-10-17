import MacManagerCore
import SwiftUI

struct IslandSettingsPage: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeading(title: state.strings("nav.island"), subtitle: state.strings("settings.island.subtitle"))
                .accessibilityIdentifier("settings.island.content")
            Surface { IslandSettingsView() }
        }
    }
}

struct IslandSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var shortcut = IslandPreferences().shortcut
    var body: some View {
        @Bindable var preferences = state.preferences
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(state.strings("island.title"), systemImage: "capsule").font(.headline)
                Spacer()
                Button(state.strings("island.open")) { state.island.showFromKeyboard() }
                    .buttonStyle(.glass).disabled(!preferences.island.enabled)
                    .accessibilityIdentifier("island.open")
            }
            Toggle(state.strings("island.enabled"), isOn: $preferences.island.enabled)
                .accessibilityIdentifier("island.enabled")
            Text(state.strings("island.sections.title")).font(.subheadline.weight(.semibold))
            ForEach(IslandSection.allCases, id: \.self) { section in
                Toggle(state.strings(section.titleKey), isOn: Binding(
                    get: { preferences.island.sections.contains(section) },
                    set: { enabled in
                        var island = preferences.island
                        island.setSection(section, enabled: enabled)
                        preferences.island = island
                    }
                ))
                .accessibilityIdentifier("island.enabled." + section.rawValue)
            }
            Text(state.strings("island.sections.help"))
                .font(.caption).foregroundStyle(.secondary)
            Toggle(state.strings("island.fullScreen"), isOn: $preferences.island.showsInFullScreen)
                .accessibilityIdentifier("island.fullScreen")
            Toggle(state.strings("launcher.shortcut.enabled"), isOn: $shortcut.enabled)
                .accessibilityIdentifier("island.shortcut.enabled")
            HStack {
                Text(state.strings("launcher.shortcut")); Spacer()
                Picker(state.strings("launcher.modifiers"), selection: $shortcut.modifiers) {
                    ForEach(LauncherShortcut.modifierChoices, id: \.1) { Text($0.0).tag($0.1) }
                }.labelsHidden().fixedSize()
                Picker(state.strings("launcher.key"), selection: $shortcut.keyCode) {
                    ForEach(LauncherShortcut.keys, id: \.1) {
                        Text($0.1 == 49 ? state.strings("launcher.space") : $0.0).tag($0.1)
                    }
                }.labelsHidden().fixedSize()
            }.disabled(!shortcut.enabled)
            if state.island.shortcutFailed {
                Label(state.strings("launcher.conflict"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button(state.strings("launcher.retry")) { state.island.updateShortcut(shortcut) }
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                Text(state.island.debugPresentationState)
                    .accessibilityIdentifier("island.debug.presentation")
                Text(state.island.debugMusicState)
                    .accessibilityIdentifier("island.debug.music")
                Text(state.island.debugPodcastsState)
                    .accessibilityIdentifier("island.debug.podcasts")
                Text(state.island.debugAnimationState)
                    .accessibilityIdentifier("island.debug.animation")
            }
            #endif
        }
        .padding(.trailing, 20)
        .onAppear { shortcut = preferences.island.shortcut }
        .onChange(of: shortcut) { _, value in state.island.updateShortcut(value) }
    }
}
