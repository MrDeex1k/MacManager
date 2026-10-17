import Foundation

/// Only values exposed by the Podcasts player, without library or on-disk data access.
public struct PodcastPlayerReading: Sendable {
    public var title = ""
    public var subtitle = ""
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
        var detail = subtitle
        if !title.isEmpty, let range = expandedMetadata.range(of: title) {
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

    public static func seconds(_ text: String) -> Double? {
        // AX timestamps can contain directional marks and a Unicode minus sign.
        let cleaned = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) &&
            !CharacterSet.whitespacesAndNewlines.contains($0) && $0.value != 0x2212 && $0 != "-" }
        let parts = String(String.UnicodeScalarView(cleaned)).split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let last = Int(parts.last!), last < 60 else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count, values.count != 3 || values[1] < 60 else { return nil }
        let seconds = values.reduce(0.0) { $0 * 60 + Double($1) }
        return seconds <= 31_536_000 ? seconds : nil
    }
}
