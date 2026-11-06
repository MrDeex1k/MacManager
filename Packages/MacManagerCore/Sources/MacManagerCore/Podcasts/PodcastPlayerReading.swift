import Foundation

/// Only values exposed by the Podcasts player, without library or on-disk data access.
public struct PodcastPlayerReading: Sendable {
    public var title = ""
    public var subtitle = ""
    public var showTitle = ""
    public var expandedMetadata = ""
    public var playing = false
    public var playbackControlLabel = ""
    public var fraction: Double?
    public var elapsedText = ""
    public var remainingText = ""
    public var backwardLabel: String?
    public var forwardLabel: String?
    public init() {}

    public var snapshot: MusicSnapshot {
        var detail = showTitle.isEmpty ? subtitle : showTitle
        if showTitle.isEmpty, !title.isEmpty, let range = expandedMetadata.range(of: title) {
            let suffix = String(expandedMetadata[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ", \n"))
            if !suffix.isEmpty { detail = suffix }
        }
        let elapsed = Self.seconds(elapsedText), remaining = Self.seconds(remainingText)
        let duration = elapsed.flatMap { elapsed in remaining.map { elapsed + $0 } }
        // Podcasts can leave isPlaying in its AX identifier stale after AXPress.
        // The live action label is authoritative in the supported PL/EN locales.
        let control = playbackControlLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isPlaying: Bool
        switch control {
        case "pause", "pauza": isPlaying = true
        case "play", "resume", "odtwarzaj", "wznów": isPlaying = false
        default: isPlaying = playing
        }
        return MusicSnapshot(availability: .ready, playback: isPlaying ? .playing : .paused,
            trackID: title.isEmpty ? nil : title + "\u{1f}" + subtitle,
            title: title, artist: detail, duration: duration, position: elapsed,
            progressFraction: fraction, previousLabel: backwardLabel, nextLabel: forwardLabel)
    }

    /// Podcasts can retain both transports, even enabled controls from a hidden view.
    /// Follow the exposed view state; use enabled controls as fallback for older trees.
    public static func transportPrefix(playerIdentifier: String = "", enabledIdentifiers: Set<String>) -> String? {
        let prefixes: [String]
        if playerIdentifier.contains("viewState=fullScreen") { prefixes = ["podcasts.nowPlaying."] }
        else if playerIdentifier.contains("viewState=mini") { prefixes = ["podcasts.miniPlayer."] }
        else { prefixes = ["podcasts.nowPlaying.", "podcasts.miniPlayer."] }
        return prefixes.first {
            enabledIdentifiers.contains($0 + "playbackTransportControl")
        }
    }

    /// Parses a player clock label as a duration in seconds. Allows a single leading minus
    /// for remaining time and rejects malformed components.
    public static func seconds(_ text: String) -> Double? {
        // AX timestamps can contain directional marks and a Unicode minus sign.
        let cleaned = text.unicodeScalars.filter { $0.properties.generalCategory != .format }
        let clock = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
        let unsigned = clock.first == "−" || clock.first == "-" ? clock.dropFirst() : clock[...]
        let parts = unsigned.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count, let last = values.last, last < 60,
              values.count != 3 || values[1] < 60 else { return nil }
        let seconds = values.reduce(0.0) { $0 * 60 + Double($1) }
        return seconds <= 31_536_000 ? seconds : nil
    }
}
