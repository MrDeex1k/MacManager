import Testing
@testable import MacManagerCore

@MainActor
private final class LifecycleParticipantSpy: ApplicationLifecycleParticipant {
    let name: String
    let events: EventRecorder

    init(name: String, events: EventRecorder) {
        self.name = name
        self.events = events
    }

    func start() { events.values.append("start:\(name)") }
    func stop() { events.values.append("stop:\(name)") }
}

@MainActor
private final class EventRecorder {
    var values: [String] = []
}

@MainActor
@Test func lifecycleStartsOnceAndTerminatesInReverseOrder() {
    let events = EventRecorder()
    let first = LifecycleParticipantSpy(name: "first", events: events)
    let second = LifecycleParticipantSpy(name: "second", events: events)
    let coordinator = ApplicationLifecycleCoordinator(participants: [first, second])

    #expect(coordinator.phase == .idle)
    coordinator.start()
    coordinator.start()
    #expect(coordinator.phase == .running)
    #expect(events.values == ["start:first", "start:second"])

    coordinator.terminate()
    coordinator.terminate()
    coordinator.start()
    #expect(coordinator.phase == .terminated)
    #expect(events.values == ["start:first", "start:second", "stop:second", "stop:first"])
}

@MainActor
@Test func lifecycleCanTerminateBeforeStarting() {
    let events = EventRecorder()
    let participant = LifecycleParticipantSpy(name: "service", events: events)
    let coordinator = ApplicationLifecycleCoordinator(participants: [participant])

    coordinator.terminate()

    #expect(coordinator.phase == .terminated)
    #expect(events.values.isEmpty)
}
