import Darwin
import Foundation
import MacManagerCore

@MainActor
enum DiagnosticReportBuilder {
    static func make(state: AppState, now: Date = Date()) -> String {
        var errors = state.diagnostics.lastErrors
        if errors[.updates] == nil, let failure = state.updates.lastFailure {
            errors[.updates] = DiagnosticErrorRecord(kind: failure.kind.rawValue, date: failure.date)
        }

        let snapshot = DiagnosticReportSnapshot(
            generatedAt: now,
            values: [
                ("app_version", bundleValue("CFBundleShortVersionString", fallback: "unknown")),
                ("app_build", bundleValue("CFBundleVersion", fallback: "unknown")),
                ("macos_version", operatingSystemVersion()),
                ("architecture", architecture),
                ("mac_model", hardwareModel()),
                ("sampling_interval_seconds", String(state.preferences.samplingInterval.rawValue)),
                ("metrics_status", metricsStatus(state.metrics)),
                ("network_status", state.network.environment.online ? "online" : "offline"),
                ("public_ip_lookup", state.network.state.rawValue),
                ("scroll_status", state.scroll.status.rawValue),
                ("scroll_permission", scrollPermission(state.scroll.status)),
                ("launch_at_login", launchAtLoginStatus(state.loginItem.state)),
                ("dock_icon", dockStatus(state.dock.state)),
                ("automatic_update_checks", state.updates.automaticChecksEnabled ? "enabled" : "disabled"),
                ("update_status", state.updates.status.rawValue),
                ("update_last_attempt", formatted(state.updates.lastAttempt)),
                ("update_last_success", formatted(state.updates.lastSuccess))
            ],
            errors: errors
        )
        return snapshot.render()
    }

    private static func bundleValue(_ key: String, fallback: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
    }

    private static func operatingSystemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "unsupported"
        #endif
    }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        let content = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: content, as: UTF8.self)
    }

    private static func metricsStatus(_ service: MetricsService) -> String {
        if service.suspended { return "suspended" }
        let states = service.snapshot.readings.values.map(\.status)
        if states.contains(.available) { return "available" }
        if states.contains(.failed) { return "failed" }
        if states.contains(.stale) { return "stale" }
        return "unavailable"
    }

    private static func scrollPermission(_ status: ScrollStatus) -> String {
        switch status {
        case .permissionRequired: "accessibilityRequired"
        case .inputMonitoringRequired: "inputMonitoringRequired"
        case .active, .starting, .interrupted, .failed, .suspended: "granted"
        case .off: "notRequested"
        }
    }

    private static func launchAtLoginStatus(_ state: LaunchAtLoginState) -> String {
        switch state {
        case .unknown: "unknown"
        case .disabled: "disabled"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .unavailable: "unavailable"
        case .failed: "failed"
        }
    }

    private static func dockStatus(_ state: DockVisibilityState) -> String {
        switch state {
        case .visible: "visible"
        case .hidden: "hidden"
        case .failed: "failed"
        }
    }

    private static func formatted(_ date: Date?) -> String {
        guard let date else { return "never" }
        return ISO8601DateFormatter().string(from: date)
    }
}
