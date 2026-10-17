import Foundation
import Testing
@testable import MacManagerCore

private actor TestMusicAdapter: MusicPlayerAdapter {
    var reads = 0
    var releases = 0
    var requests = 0
    var commands: [MusicCommand] = []
    var access: MusicAvailability
    var delay: Duration
    var index = 1
    init(access: MusicAvailability = .ready, delay: Duration = .zero) { self.access = access; self.delay = delay }
    func read() async -> MusicSnapshot {
        reads += 1
        try? await Task.sleep(for: delay)
        return MusicSnapshot(availability: access, playback: .playing, trackID: "\(index)", title: "Test",
                             duration: 180, position: 20, artwork: Data([1, 2, 3]))
    }
    func perform(_ command: MusicCommand) -> MusicAvailability { commands.append(command); index += 1; return access }
    func requestAccess() -> MusicAvailability { requests += 1; access = .ready; return .ready }
    func releaseArtwork() { releases += 1 }
}

@Test @MainActor func musicOnlyReadsWhileVisibleAndReleasesPrivateState() async throws {
    let adapter = TestMusicAdapter()
    let service = MusicService(adapter: adapter)
    #expect(await adapter.reads == 0)
    service.setVisible(true)
    #expect(await waitUntil { service.snapshot.availability == .ready })
    service.setVisible(false)
    #expect(!service.hasPendingWork && service.snapshot.artwork == nil && service.snapshot.title.isEmpty)
    #expect(await waitUntil { await adapter.releases == 1 })
    let reads = await adapter.reads
    try await Task.sleep(for: .milliseconds(1100))
    #expect(await adapter.reads == reads)
    service.setVisible(true)
    #expect(await waitUntil { service.snapshot.availability == .ready })
    service.setVisible(false)
}
@Test @MainActor func musicIgnoresReadThatCompletesAfterHiding() async {
    let adapter = TestMusicAdapter(delay: .milliseconds(100))
    let service = MusicService(adapter: adapter)
    service.setVisible(true)
    #expect(await waitUntil { await adapter.reads == 1 })
    service.setVisible(false)
    #expect(await waitUntil { await adapter.releases == 1 })
    #expect(service.snapshot.availability == .idle && service.snapshot.artwork == nil && !service.hasPendingWork)
}
@Test @MainActor func musicPermissionIsExplicitAndCommandsRequireVisibleReadyPlayer() async {
    let adapter = TestMusicAdapter(access: .denied)
    let service = MusicService(adapter: adapter)
    service.setVisible(true)
    #expect(await waitUntil { service.snapshot.availability == .denied })
    service.perform(.next)
    let commands = await adapter.commands
    let requests = await adapter.requests
    #expect(commands.isEmpty && requests == 0)
    service.requestAccess()
    #expect(await waitUntil { service.snapshot.availability == .ready && !service.busy })
    service.perform(.playPause)
    service.perform(.next) // Do not queue several transport commands while one is pending.
    #expect(await waitUntil { await adapter.commands.count == 1 && !service.busy })
    #expect(await adapter.commands == [.playPause])
    service.setVisible(false)
    service.perform(.previous)
    #expect(await adapter.commands.count == 1)
}
@Test func musicTimeValuesAreFiniteAndClamped() {
    let unknown = MusicSnapshot(duration: .infinity, position: .nan)
    #expect(unknown.duration == nil && unknown.position == nil)
    let end = MusicSnapshot(duration: 60, position: 90)
    #expect(end.position == 60)
    let start = MusicSnapshot(duration: 60, position: -3)
    #expect(start.position == 0)
}

@Test @MainActor func independentPlayersStopReadsWhenSwitchingSources() async {
    let musicAdapter = TestMusicAdapter(), podcastAdapter = TestMusicAdapter()
    let music = MusicService(adapter: musicAdapter), podcast = MusicService(adapter: podcastAdapter)
    music.setVisible(true)
    #expect(await waitUntil { music.snapshot.availability == .ready })
    #expect(await podcastAdapter.reads == 0)
    music.setVisible(false); podcast.setVisible(true)
    #expect(await waitUntil { podcast.snapshot.availability == .ready })
    let musicReads = await musicAdapter.reads
    try? await Task.sleep(for: .milliseconds(1100))
    #expect(await musicAdapter.reads == musicReads)
    #expect(!music.hasPendingWork && music.snapshot.title.isEmpty)
    podcast.setVisible(false)
    #expect(!podcast.hasPendingWork && podcast.snapshot.artwork == nil)
}

/// Keeps reads pending even after cancellation, like an in-flight synchronous player request.
private actor ControlledMusicAdapter: MusicPlayerAdapter {
    private var pending: [Int: CheckedContinuation<MusicSnapshot, Never>] = [:]
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var holdCleanup: Bool
    private var activeReads = 0
    var reads = 0
    var releases = 0
    var maximumConcurrentReads = 0
    init(holdCleanup: Bool = false) { self.holdCleanup = holdCleanup }
    func read() async -> MusicSnapshot {
        reads += 1
        let number = reads
        activeReads += 1
        maximumConcurrentReads = max(maximumConcurrentReads, activeReads)
        defer { activeReads -= 1 }
        return await withCheckedContinuation { pending[number] = $0 }
    }
    func finishRead(_ number: Int, title: String) {
        pending.removeValue(forKey: number)?.resume(returning:
            MusicSnapshot(availability: .ready, playback: .playing, trackID: title, title: title, artwork: Data([1, 2, 3])))
    }
    func perform(_ command: MusicCommand) -> MusicAvailability { .ready }
    func requestAccess() -> MusicAvailability { .ready }
    func releaseArtwork() async {
        releases += 1
        if holdCleanup { await withCheckedContinuation { releaseContinuation = $0 } }
    }
    func finishCleanup() {
        holdCleanup = false
        releaseContinuation?.resume(); releaseContinuation = nil
    }
}

@Test @MainActor func musicRefreshPreservesSnapshotAndCacheAndSerializesPendingReads() async {
    let adapter = ControlledMusicAdapter()
    let service = MusicService(adapter: adapter)
    service.setVisible(true)
    #expect(await waitUntil { await adapter.reads == 1 })
    await adapter.finishRead(1, title: "Current track")
    #expect(await waitUntil { service.snapshot.title == "Current track" })

    service.refresh()
    #expect(service.visible && service.snapshot.availability == .ready)
    #expect(service.snapshot.title == "Current track" && service.snapshot.artwork == Data([1, 2, 3]))
    #expect(await waitUntil { await adapter.reads == 2 })
    #expect(await adapter.releases == 0)
    service.refresh() // Invalidate the pending response without starting an overlapping read.
    for _ in 0..<20 { await Task.yield() }
    #expect(await adapter.reads == 2)
    await adapter.finishRead(2, title: "Obsolete response")
    #expect(await waitUntil { await adapter.reads == 3 })
    #expect(service.snapshot.title == "Current track")
    #expect(await adapter.maximumConcurrentReads == 1)
    await adapter.finishRead(3, title: "Updated track")
    #expect(await waitUntil { service.snapshot.title == "Updated track" })
    #expect(await adapter.releases == 0)

    service.setVisible(false)
    service.refresh() // A hidden section must not restart its reader.
    #expect(service.snapshot.title.isEmpty && service.snapshot.artwork == nil && !service.hasPendingWork)
    #expect(await waitUntil { await adapter.releases == 1 })
}

@Test @MainActor func musicRefreshWaitsForPendingVisibilityCleanup() async {
    let adapter = ControlledMusicAdapter(holdCleanup: true)
    let service = MusicService(adapter: adapter)
    service.setVisible(true)
    #expect(await waitUntil { await adapter.reads == 1 })
    await adapter.finishRead(1, title: "Before hiding")
    #expect(await waitUntil { service.snapshot.title == "Before hiding" })
    service.setVisible(false)
    #expect(await waitUntil { await adapter.releases == 1 })
    service.setVisible(true)
    service.refresh()
    for _ in 0..<20 { await Task.yield() }
    #expect(await adapter.reads == 1)
    await adapter.finishCleanup()
    #expect(await waitUntil { await adapter.reads == 2 })
    await adapter.finishRead(2, title: "After cleanup")
    #expect(await waitUntil { service.snapshot.title == "After cleanup" })
    #expect(await adapter.maximumConcurrentReads == 1)
    service.setVisible(false)
    #expect(await waitUntil { await adapter.releases == 2 })
}
