import Foundation
import Observation

@MainActor @Observable
public final class NetworkService {
    public private(set) var environment = NetworkEnvironment(online: false)
    public private(set) var state: PublicIPState = .waiting
    public private(set) var publicAddress: String?
    public private(set) var observedAt: Date?
    public private(set) var enabled: Bool
    @ObservationIgnored private let lookup: @Sendable () async throws -> String
    @ObservationIgnored private var request: Task<String, Error>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastAttempt: TimeInterval?
    @ObservationIgnored private var nextAttempt: TimeInterval = 0
    @ObservationIgnored private var receivedEnvironment = false
    @ObservationIgnored private var suspended = false

    public init(enabled: Bool = true, lookup: @escaping @Sendable () async throws -> String = PublicIPClient.lookup) {
        self.enabled = enabled; self.lookup = lookup
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

    public func pathChanged(now: TimeInterval) {
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

    public func refresh(now: TimeInterval, manual: Bool = false) async {
        guard enabled, !suspended, receivedEnvironment, environment.online, request == nil,
              manual || now >= nextAttempt else { return }
        lastAttempt = now; nextAttempt = now + 900
        publicAddress = nil; observedAt = nil; state = .loading
        let token = generation
        let task = Task { try await lookup() }
        request = task
        defer { if generation == token { request = nil } }
        do {
            let address = try await task.value
            guard generation == token else { return }
            guard IPv4.isPublic(address) else { state = .failed; return }
            publicAddress = address; observedAt = Date(); state = .available
        } catch {
            guard generation == token else { return }
            state = .failed
        }
    }

    private var restingState: PublicIPState {
        if !enabled { return .disabled }
        if suspended { return .suspended }
        return environment.online ? .waiting : .offline
    }

    private func invalidate() {
        generation += 1; request?.cancel(); request = nil
        publicAddress = nil; observedAt = nil
    }
}
