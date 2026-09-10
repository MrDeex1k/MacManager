import Foundation

@MainActor
func waitUntil(
    timeout: Duration = .seconds(1),
    condition: () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    repeat {
        if await condition() { return true }
        await Task.yield()
    } while clock.now < deadline
    return await condition()
}
