import MacManagerCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences
        let strings = state.strings
        VStack(alignment: .leading, spacing: 28) {
            PageHeading(title: strings("settings.title"), subtitle: strings("settings.subtitle"))
            Surface {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Label(strings("settings.language"), systemImage: "globe")
                            .font(.headline)
                        Spacer()
                        Picker(strings("settings.language"), selection: $preferences.language) {
                            Text(strings("language.system")).tag(AppLanguage.system)
                            Text("English").tag(AppLanguage.english)
                            Text("Polski").tag(AppLanguage.polish)
                        }
                        .labelsHidden()
                        .frame(width: 185)
                        .accessibilityIdentifier("settings.language")
                    }
                    Text(strings("settings.language.note"))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Divider()
                    HStack {
                        Label(strings("settings.appearance"), systemImage: "moon")
                            .font(.headline)
                        Spacer()
                        Text(strings("settings.dark")).foregroundStyle(.secondary)
                    }
                    Text(strings("settings.appearance.note"))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            HStack {
                Text(strings("metrics.interval")).font(.headline)
                Spacer()
                Picker(strings("metrics.interval"), selection: $preferences.samplingInterval) {
                    ForEach(SamplingInterval.allCases) { interval in
                        Text("\(interval.rawValue) s").tag(interval)
                    }
                }
                .labelsHidden().frame(width: 185)
                .accessibilityIdentifier("metrics.interval")
                .onChange(of: preferences.samplingInterval) { _, interval in
                    state.metrics.setInterval(interval)
                }
            }
            Divider()
            ScrollSettingsView()
            Divider()
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    Label(strings("settings.privacy.title"), systemImage: "lock.shield")
                        .font(.headline)
                    Text(strings("settings.privacy.body"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Text("Mac Manager").fontWeight(.medium)
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
