import Foundation
import Testing
@testable import MacManagerCore

struct PodcastTests {
    @Test func parsesOnlyRealPlayerTimestamps() {
        #expect(PodcastPlayerReading.seconds("\u{200e}−55:57") == 3357)
        #expect(PodcastPlayerReading.seconds("1:02:03") == 3723)
        #expect(PodcastPlayerReading.seconds("0:00") == 0)
        for invalid in ["", "Not playing", "12:90", "1:60:00", "3", "NaN", "0::1"] {
            #expect(PodcastPlayerReading.seconds(invalid) == nil)
        }
    }
    @Test func miniPlayerDoesNotInventMissingTimesOrArtwork() {
        var reading = PodcastPlayerReading()
        reading.title = "Episode, with a comma"; reading.subtitle = "17 October"
        reading.fraction = 0.25
        let value = reading.snapshot
        #expect(value.title == reading.title && value.artist == reading.subtitle)
        #expect(value.duration == nil && value.position == nil && value.artwork == nil)
        #expect(value.progressFraction == 0.25 && value.trackID != nil)
    }
    @Test func expandedPlayerUsesShowAndKnownTimestamps() {
        var reading = PodcastPlayerReading()
        reading.title = "Episode, with a comma"; reading.subtitle = "17 October"
        reading.expandedMetadata = "17 October, Episode, with a comma, Show name"
        reading.elapsedText = "02:00"; reading.remainingText = "−28:00"
        reading.playing = true
        let value = reading.snapshot
        #expect(value.artist == "Show name" && value.duration == 1800 && value.position == 120)
        #expect(value.playback == .playing)
        reading.title = ""
        #expect(reading.snapshot.trackID == nil)
    }
    @Test func progressRejectsInvalidAndClampsOutOfRange() {
        #expect(MusicSnapshot(progressFraction: .nan).progressFraction == nil)
        #expect(MusicSnapshot(progressFraction: .infinity).progressFraction == nil)
        #expect(MusicSnapshot(progressFraction: 1.4).progressFraction == 1)
        #expect(MusicSnapshot(progressFraction: -1).progressFraction == 0)
    }
    @Test func liveTransportLabelOverridesStalePlayerIdentifier() {
        var reading = PodcastPlayerReading()
        for label in ["Pause", "Pauza"] {
            reading.playing = false; reading.playbackControlLabel = label
            #expect(reading.snapshot.playback == .playing)
        }
        for label in ["Play", "Odtwarzaj", "Resume", "Wznów"] {
            reading.playing = true; reading.playbackControlLabel = label
            #expect(reading.snapshot.playback == .paused)
        }
        reading.playbackControlLabel = ""
        #expect(reading.snapshot.playback == .playing)
    }

}
