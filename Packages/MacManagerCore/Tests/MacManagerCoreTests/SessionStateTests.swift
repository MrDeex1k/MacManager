import Testing
@testable import MacManagerCore

@Test func wakingDoesNotResumeLockedOrInactiveSession() {
    var state = SessionState()
    state.set(.lock, active: true)
    state.set(.inactiveSession, active: true)
    state.set(.sleep, active: true)
    #expect(state.sleeping && state.suspended)
    state.set(.sleep, active: false)
    #expect(!state.sleeping && state.suspended)
    state.set(.lock, active: false)
    #expect(state.suspended)
    state.set(.inactiveSession, active: false)
    #expect(!state.suspended)
}
