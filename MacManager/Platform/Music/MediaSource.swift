import MacManagerCore

/// Source-specific presentation and capabilities; adapters own protocol differences.
enum MediaSource: String, CaseIterable, Hashable {
    case music, podcast
    var bundleID: String { self == .music ? "com.apple.Music" : "com.apple.podcasts" }
    var productName: String { self == .music ? "Apple Music" : "Apple Podcasts" }
    var artworkSymbol: String { self == .music ? "music.note" : "dot.radiowaves.left.and.right" }
    var previousSymbol: String { self == .music ? "backward.end.fill" : "gobackward" }
    var nextSymbol: String { self == .music ? "forward.end.fill" : "goforward" }
    var emptyTitleKey: String { self == .music ? "music.noTrack" : "podcast.noEpisode" }
    var connectionAvailability: MusicAvailability { self == .music ? .needsPermission : .accessibilityRequired }
    var supportsAutomationRecovery: Bool { self == .music }
    var requiresTrackForPlayPause: Bool { self == .podcast }
    var showsUnknownArtist: Bool { self == .music }
    var supportsFractionProgress: Bool { self == .podcast }
    var playbackNotification: String? { self == .music ? "com.apple.Music.playerInfo" : nil }
    var section: IslandSection { self == .music ? .music : .podcast }
    func identifier(_ key: String) -> String { key.replacingOccurrences(of: "music.", with: rawValue + ".") }
}
