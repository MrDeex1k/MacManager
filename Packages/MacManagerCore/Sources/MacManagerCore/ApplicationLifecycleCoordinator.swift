import Observation

@MainActor
public protocol ApplicationLifecycleParticipant: AnyObject {
    func start()
    func stop()
}

public enum ApplicationLifecyclePhase: Equatable, Sendable {
    case idle
    case running
    case terminated
}

@MainActor
@Observable
public final class ApplicationLifecycleCoordinator {
    public private(set) var phase: ApplicationLifecyclePhase = .idle

    @ObservationIgnored private let participants: [any ApplicationLifecycleParticipant]

    public init(participants: [any ApplicationLifecycleParticipant]) {
        self.participants = participants
    }

    public func start() {
        guard phase == .idle else { return }
        phase = .running
        participants.forEach { $0.start() }
    }

    public func terminate() {
        guard phase != .terminated else { return }
        let wasRunning = phase == .running
        phase = .terminated
        if wasRunning {
            participants.reversed().forEach { $0.stop() }
        }
    }
}
