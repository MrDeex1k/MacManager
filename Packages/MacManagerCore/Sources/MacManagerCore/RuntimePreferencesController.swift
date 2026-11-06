import Foundation

/// Applies persisted settings regardless of which screen or command changed them.
@MainActor
public final class RuntimePreferencesController: ApplicationLifecycleParticipant {
    private struct Values: Equatable {
        var interval: SamplingInterval
        var scroll: Bool
        var axes: ScrollAxes
        var publicIP: Bool
    }
    private let preferences: PreferencesStore
    private let setInterval: (SamplingInterval) -> Void
    private let setScroll: (Bool) -> Void
    private let setAxes: (ScrollAxes) -> Void
    private let setPublicIP: (Bool) -> Void
    private let observation = ObservationSubscription()
    private var applied: Values?
    private var running = false

    public init(preferences: PreferencesStore, setInterval: @escaping (SamplingInterval) -> Void,
                setScroll: @escaping (Bool) -> Void, setAxes: @escaping (ScrollAxes) -> Void,
                setPublicIP: @escaping (Bool) -> Void) {
        self.preferences = preferences; self.setInterval = setInterval
        self.setScroll = setScroll; self.setAxes = setAxes; self.setPublicIP = setPublicIP
    }

    public func start() {
        guard !running else { return }
        running = true
        observation.start(read: { [preferences] in
            Values(interval: preferences.samplingInterval, scroll: preferences.reverseMouseScroll,
                   axes: preferences.scrollAxes, publicIP: preferences.publicIPEnabled)
        }, apply: { [weak self] value in
            guard let self else { return }
            if value.interval != applied?.interval { setInterval(value.interval) }
            if value.axes != applied?.axes { setAxes(value.axes) }
            if value.scroll != applied?.scroll { setScroll(value.scroll) }
            if value.publicIP != applied?.publicIP { setPublicIP(value.publicIP) }
            applied = value
        })
    }

    public func stop() {
        running = false
        observation.stop()
        applied = nil
    }
}
