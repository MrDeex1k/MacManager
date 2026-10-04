import AppKit
import MacManagerCore
import SwiftUI

struct UpdateSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var availabilityDate = Date()
    @State private var clockRevision = 0

    var body: some View {
        let strings = state.strings
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
            .padding(.trailing, 20)

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
            .padding(.trailing, 20)

            HStack(spacing: 8) {
                Button(strings("updates.check"), systemImage: "arrow.clockwise") {
                    Task { await state.checkForUpdates() }
                }
                .buttonStyle(.glass)
                .disabled(!state.updates.manualCheckIsAvailable(at: availabilityDate))
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
        .task(id: CooldownID(lastAttempt: state.updates.lastAttempt, clockRevision: clockRevision, visible: state.mainWindowContentVisible)) {
            guard state.mainWindowContentVisible else { return }
            availabilityDate = Date()
            guard let lastAttempt = state.updates.lastAttempt else { return }
            let deadline = lastAttempt.addingTimeInterval(UpdateService.manualCooldown)
            guard deadline > availabilityDate else { return }
            do { try await Task.sleep(for: .seconds(deadline.timeIntervalSinceNow)) }
            catch { return }
            availabilityDate = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            clockRevision &+= 1
        }
    }

    private struct CooldownID: Equatable {
        let lastAttempt: Date?
        let clockRevision: Int
        let visible: Bool
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
