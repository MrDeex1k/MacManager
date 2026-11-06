import Foundation
import Observation

@MainActor @Observable
public final class NetworkService {
    public private(set) var environment = NetworkEnvironment(online: false)
    public private(set) var state: PublicIPState = .waiting
    public private(set) var publicAddress: String?
    public private(set) var observedAt: Date?
    public private(set) var enabled: Bool
    public private(set) var refreshIntervalSeconds: Double = 900
    @ObservationIgnored private var periodicDeadline = false
    public var nextRefreshDeadline: TimeInterval? {
        enabled && !suspended && receivedEnvironment && environment.online && request == nil ? nextAttempt : nil
    }
    /// Updates the regular lookup cadence without replacing a route-change or cancellation deadline.
    public func setRefreshInterval(_ seconds: Double) {
        guard seconds.isFinite, seconds >= 30 else { return }
        refreshIntervalSeconds = seconds
        if periodicDeadline, let lastAttempt { nextAttempt = lastAttempt + seconds }
    }
    @ObservationIgnored private let lookup: @Sendable () async throws -> String
    @ObservationIgnored private let diagnostics: DiagnosticsStore?
    @ObservationIgnored private var request: Task<String, Error>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastAttempt: TimeInterval?
    @ObservationIgnored private var nextAttempt: TimeInterval = 0
    @ObservationIgnored private var receivedEnvironment = false
    @ObservationIgnored private var suspended = false

    /// Accepts an injectable public address lookup and optional diagnostic recorder.
    public init(enabled: Bool = true, diagnostics: DiagnosticsStore? = nil,
                lookup: @escaping @Sendable () async throws -> String = PublicIPClient.lookup) {
        self.enabled = enabled; self.diagnostics = diagnostics; self.lookup = lookup
        if !enabled { state = .disabled }
    }

    public func update(_ environment: NetworkEnvironment, now: TimeInterval) {
        guard !receivedEnvironment || environment != self.environment else { return }
        let first = !receivedEnvironment
        receivedEnvironment = true
        self.environment = environment
        invalidate()
        state = restingState
        nextAttempt = max(now + (first ? 0 : 2), (lastAttempt ?? -.infinity) + 30)
    }

    /// Clears route-dependent public data immediately while keeping the last local interface snapshot.
    public func pathChanged(now: TimeInterval, online: Bool? = nil) {
        if let online, online != environment.online {
            environment = NetworkEnvironment(online: online, addresses: environment.addresses,
                                             primary: environment.primary, tunnels: environment.tunnels)
        }
        invalidate(); state = restingState
        nextAttempt = max(now + 2, (lastAttempt ?? -.infinity) + 30)
    }

    public func setEnabled(_ enabled: Bool, now: TimeInterval) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        invalidate(); state = restingState
        nextAttempt = max(now, (lastAttempt ?? -.infinity) + 30)
    }

    public func setSuspended(_ suspended: Bool, now: TimeInterval) {
        guard suspended != self.suspended else { return }
        self.suspended = suspended
        invalidate(); state = restingState
        nextAttempt = max(now + 2, (lastAttempt ?? -.infinity) + 30)
    }

    public func refreshIsDue(at now: TimeInterval) -> Bool {
        enabled && !suspended && receivedEnvironment && environment.online && request == nil && now >= nextAttempt
    }

    /// Starts one lookup for the current online environment. Publishes only validated results
    /// from the current generation and treats cancellation as a deferred retry.
    public func refresh(now: TimeInterval, manual: Bool = false) async {
        guard !Task.isCancelled, enabled, !suspended, receivedEnvironment, environment.online, request == nil,
              manual || now >= nextAttempt else { return }
        lastAttempt = now; nextAttempt = now + refreshIntervalSeconds; periodicDeadline = true
        publicAddress = nil; observedAt = nil; state = .loading
        let token = generation
        let task = Task {
            try Task.checkCancellation()
            return try await lookup()
        }
        request = task
        defer { if generation == token { request = nil } }
        do {
            let address = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard generation == token else { return }
            try Task.checkCancellation()
            guard IPv4.isPublic(address) else { throw PublicIPClient.Failure.invalidResponse }
            publicAddress = address; observedAt = Date(); state = .available
        } catch {
            guard generation == token else { return }
            if Task.isCancelled || task.isCancelled {
                periodicDeadline = false
                nextAttempt = now + 30
                state = restingState
                return
            }
            let kind: String
            if error is PublicIPClient.Failure { kind = "invalidResponse" }
            else if let error = error as? URLError, error.code == .timedOut { kind = "timeout" }
            else if let error = error as? URLError, [.notConnectedToInternet, .networkConnectionLost].contains(error.code) {
                kind = "offline"
            } else { kind = "transport" }
            diagnostics?.record(.network, kind: kind)
            MacManagerLog.network.error("Public address lookup failed: \(kind, privacy: .public)")
            state = .failed
        }
    }

    private var restingState: PublicIPState {
        if !enabled { return .disabled }
        if suspended { return .suspended }
        return environment.online ? .waiting : .offline
    }

    private func invalidate() {
        periodicDeadline = false
        generation += 1; request?.cancel(); request = nil
        publicAddress = nil; observedAt = nil
    }
}
