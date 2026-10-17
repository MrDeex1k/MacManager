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
