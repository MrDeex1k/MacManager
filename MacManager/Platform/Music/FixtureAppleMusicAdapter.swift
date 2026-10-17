#if DEBUG
import Foundation
import MacManagerCore

actor FixtureAppleMusicAdapter: MusicPlayerAdapter {
    private var playback: MusicPlayback = .paused
    private var availability: MusicAvailability
    private var index = 1
    init(arguments: [String]) {
        availability = arguments.contains("--music-denied") ? .denied :
            arguments.contains("--music-not-running") ? .notRunning :
            arguments.contains("--music-needs-permission") ? .needsPermission : .ready
    }
    func read() -> MusicSnapshot {
        MusicSnapshot(availability: availability, playback: playback, trackID: "fixture-\(index)",
                      title: "Test song \(index)", artist: "Fixture artist", album: "Fixture album", duration: 180, position: 42)
    }
    func perform(_ command: MusicCommand) -> MusicAvailability {
        guard availability == .ready else { return availability }
        switch command {
        case .playPause: playback = playback == .playing ? .paused : .playing
        case .next: index += 1
        case .previous: index = max(1, index - 1)
        }
        return .ready
    }
    func requestAccess() -> MusicAvailability { availability = .ready; return .ready }
    func releaseArtwork() {}
}
#endif
