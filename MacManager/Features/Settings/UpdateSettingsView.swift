import AppKit
import MacManagerCore
import SwiftUI

struct UpdateSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let strings = state.strings
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(strings("updates.title"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    Spacer()
                    Toggle(
                        strings("updates.automatic"),
                        isOn: Binding(
                            get: { state.updates.automaticChecksEnabled },
                            set: { state.setAutomaticUpdateChecksEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .accessibilityLabel(strings("updates.automatic"))
                    .accessibilityIdentifier("updates.automatic")
                }

                Text(strings("updates.note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusText)
                            .font(.callout.weight(.medium))
                            .accessibilityIdentifier("updates.status")
                        if state.updates.status == .failed, let release = state.updates.availableRelease {
                            Text(
                                String(
                                    format: strings("updates.known"),
                                    locale: state.preferences.locale,
                                    release.version.description
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    dateRow(label: strings("updates.lastAttempt"), date: state.updates.lastAttempt)
                    if state.updates.lastSuccess != state.updates.lastAttempt {
                        dateRow(label: strings("updates.lastSuccess"), date: state.updates.lastSuccess)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button(strings("updates.check"), systemImage: "arrow.clockwise") {
                        Task { await state.checkForUpdates() }
                    }
                    .buttonStyle(.glass)
                    .disabled(!state.updates.manualCheckIsAvailable(at: context.date))
                    .accessibilityIdentifier("updates.check")

                    if let release = state.updates.availableRelease {
                        Button(strings("updates.open"), systemImage: "safari") {
                            NSWorkspace.shared.open(release.pageURL)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("updates.openRelease")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("updates.content")
        }
    }

    private var statusText: String {
        let strings = state.strings
        if state.updates.status == .updateAvailable, let release = state.updates.availableRelease {
            return String(
                format: strings("updates.status.updateAvailable"),
                locale: state.preferences.locale,
                release.version.description
            )
        }
        if state.updates.status == .failed, let failure = state.updates.lastFailure {
            return strings("updates.error.\(failure.kind.rawValue)")
        }
        return strings("updates.status.\(state.updates.status.rawValue)")
    }

    private var statusSymbol: String {
        switch state.updates.status {
        case .checking: "arrow.triangle.2.circlepath"
        case .upToDate: "checkmark.circle.fill"
        case .updateAvailable: "arrow.down.circle.fill"
        case .developmentBuild: "hammer.circle.fill"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle.fill"
        case .neverChecked, .noPublicRelease: "info.circle"
        }
    }

    private var statusColor: Color {
        switch state.updates.status {
        case .upToDate, .updateAvailable, .developmentBuild:
            AppTheme.accent
        case .failed:
            .orange
        default:
            .secondary
        }
    }

    private func dateRow(label: String, date: Date?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(date.map(formatted) ?? state.strings("updates.never"))
                .monospacedDigit()
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(state.preferences.locale)
        )
    }
}
