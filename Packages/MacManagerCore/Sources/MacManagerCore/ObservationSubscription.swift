import Observation

/// One rearming observation per owner. Scheduling work must not create subscriptions.
@MainActor
public final class ObservationSubscription {
    private var generation = 0
    private var refresh: (() -> Void)?
    public init() {}

    public func start<Value>(read: @escaping @MainActor () -> Value,
                             apply: @escaping @MainActor (Value) -> Void) {
        generation += 1
        let token = generation
        refresh = { [weak self] in self?.observe(token, read: read, apply: apply) }
        refresh?()
    }

    public func stop() { generation += 1; refresh = nil }

    private func observe<Value>(_ token: Int, read: @escaping @MainActor () -> Value,
                                apply: @escaping @MainActor (Value) -> Void) {
        guard token == generation else { return }
        let value = withObservationTracking { read() } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, token == self.generation else { return }
                self.refresh?()
            }
        }
        // Applying a value may read other models; those are not dependencies of this observation.
        apply(value)
    }
}
