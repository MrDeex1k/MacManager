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

    @Test func expandedTransportWinsOverRetainedMiniPlayerControls() {
        let mini = "podcasts.miniPlayer.playbackTransportControl"
        let expanded = "podcasts.nowPlaying.playbackTransportControl"
        #expect(PodcastPlayerReading.transportPrefix(enabledIdentifiers: [mini, expanded]) == "podcasts.nowPlaying.")
        // The full-screen AX tree retains the disabled mini player. Only enabled IDs enter this set.
        #expect(PodcastPlayerReading.transportPrefix(enabledIdentifiers: [expanded]) == "podcasts.nowPlaying.")
        #expect(PodcastPlayerReading.transportPrefix(enabledIdentifiers: [mini]) == "podcasts.miniPlayer.")
        #expect(PodcastPlayerReading.transportPrefix(enabledIdentifiers: []) == nil)
        #expect(PodcastPlayerReading.transportPrefix(enabledIdentifiers: ["podcasts.shelfItemSubComponent.playControls"]) == nil)
    }

    @Test func separateExpandedShowTitleDoesNotDependOnCombinedLabelPunctuation() {
        var reading = PodcastPlayerReading()
        reading.title = "Episode, with a comma"
        reading.subtitle = "A show, with a comma"
        reading.showTitle = reading.subtitle
        // The combined AX description may be absent or expose a different ordering.
        for combined in ["", "A show, with a comma, Episode, with a comma, 3 November"] {
            reading.expandedMetadata = combined
            #expect(reading.snapshot.title == "Episode, with a comma")
            #expect(reading.snapshot.artist == "A show, with a comma")
        }
    }

    @Test func compactPlayerDoesNotTargetEnabledControlsFromHiddenExpandedView() {
        let mini = "podcasts.miniPlayer.playbackTransportControl"
        let expanded = "podcasts.nowPlaying.playbackTransportControl"
        let compactID = "podcasts.miniPlayer.contentView[viewState=mini,isPlaying=false]"
        let expandedID = "podcasts.miniPlayer.contentView[viewState=fullScreen,isPlaying=false]"
        #expect(PodcastPlayerReading.transportPrefix(playerIdentifier: compactID, enabledIdentifiers: [mini, expanded]) == "podcasts.miniPlayer.")
        #expect(PodcastPlayerReading.transportPrefix(playerIdentifier: expandedID, enabledIdentifiers: [mini, expanded]) == "podcasts.nowPlaying.")
        // A partial scan or disabled active transport must not redirect a command to hidden controls.
        #expect(PodcastPlayerReading.transportPrefix(playerIdentifier: compactID, enabledIdentifiers: [expanded]) == nil)
        #expect(PodcastPlayerReading.transportPrefix(playerIdentifier: expandedID, enabledIdentifiers: [mini]) == nil)
    }

}
