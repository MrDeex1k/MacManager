#if DEBUG
import Foundation
import MacManagerCore

actor FixturePodcastsAdapter: MusicPlayerAdapter {
    private var playing = false
    private var position = 120.0
    private var access: MusicAvailability
    init(arguments: [String]) {
        access = arguments.contains("--podcast-access-required") ? .accessibilityRequired :
            arguments.contains("--podcast-window-required") ? .windowRequired : .ready
    }
    func read() -> MusicSnapshot {
        guard access == .ready else { return MusicSnapshot(availability: access) }
        return MusicSnapshot(availability: .ready, playback: playing ? .playing : .paused,
            trackID: "podcast-fixture", title: "Test episode", artist: "Test podcast", duration: 1800, position: position,
            previousLabel: "Skip back", nextLabel: "Skip forward")
    }
    func perform(_ command: MusicCommand) -> MusicAvailability {
        guard access == .ready else { return access }
        switch command {
        case .playPause: playing.toggle()
        case .previous: position = max(0, position - 15)
        case .next: position = min(1800, position + 30)
        }
        return .ready
    }
    func requestAccess() -> MusicAvailability { access = .ready; return access }
    func releaseArtwork() {}
}
#endif
