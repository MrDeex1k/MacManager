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
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("settings.language")
                    }
                    .padding(.trailing, 20)
                    Text(strings("settings.language.note"))
                        .foregroundStyle(.secondary)
                        .font(.callout)
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
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("metrics.interval")
                .onChange(of: preferences.samplingInterval) { _, interval in
                    state.metrics.setInterval(interval)
                }
            }
            .padding(.trailing, 20)
            Divider()
            LaunchAtLoginSettingsView()
            Divider()
            UpdateSettingsView()
            Divider()
            DiagnosticsView()
            HStack {
                Text("Mac Manager").fontWeight(.medium)
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.0")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
