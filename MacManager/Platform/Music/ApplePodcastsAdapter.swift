import AppKit
import OSLog
@preconcurrency import ApplicationServices
import QuartzCore
import MacManagerCore

/// Public Accessibility actions targeted at Podcasts, never global keys or private MediaRemote.
/// Reads only a bounded player subtree. A closed/unavailable window is reported explicitly.
actor ApplePodcastsAdapter: MusicPlayerAdapter {
    private let artworkAccess: PodcastArtworkAccess
    init(artworkAccess: PodcastArtworkAccess) { self.artworkAccess = artworkAccess }
    private struct ArtworkKey: Equatable {
        let title: String
        let subtitle: String
        let showTitle: String
        let expandedMetadata: String
    }
    private var artworkKey: ArtworkKey?
    private var artworkAttempt: TimeInterval = 0
    private var cachedEpisode: (title: String, show: String, id: String, artwork: Data?)?

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func text(_ element: AXUIElement?, _ name: String = kAXDescriptionAttribute) -> String {
        guard let element else { return "" }
        return attribute(element, name) as? String ?? ""
    }
    private func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private func timestamp(_ element: AXUIElement?) -> String {
        guard let element else { return "" }
        // Newer Podcasts versions label the button "Elapsed" / "Remaining".
        // Read the clock text when exposed, without guessing from spoken durations.
        for name in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXValueDescriptionAttribute] {
            let value = text(element, name)
            if PodcastPlayerReading.seconds(value) != nil { return value }
        }
        return ""
    }
    private func application() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.podcasts").first,
              !app.isTerminated else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.10)
        return element
    }
    private struct Player {
        var elements: [String: AXUIElement] = [:]
        var playerID = ""
        var fallbackTitle = ""
    }
    private func player(_ root: AXUIElement) -> Player {
        let signposter = OSSignposter(subsystem: "dev.macmanager.MacManager", category: "PointsOfInterest")
        let interval = signposter.beginInterval("AXPlayerScan", id: signposter.makeSignpostID())
        defer { signposter.endInterval("AXPlayerScan", interval) }
        let deadline = CACurrentMediaTime() + 0.35
        var result = Player()
        // The application children include a large menu tree, often before windows.
        // Start at AXWindows so background reads reach the player within the budget.
        let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        var queue: [(AXUIElement, Int, Bool)] = windows.prefix(4).map { ($0, 0, false) }
        var index = 0
        while index < queue.count && index < 400 && !Task.isCancelled && CACurrentMediaTime() < deadline {
            let (element, depth, insideMetadata) = queue[index]; index += 1
            let id = text(element, kAXIdentifierAttribute)
            if id.hasPrefix("podcasts.miniPlayer.contentView[") { result.playerID = id }
            if result.playerID.contains("viewState=mini"), id.hasPrefix("podcasts.nowPlaying.") { continue }
            if id.hasPrefix("podcasts.miniPlayer.") || id.hasPrefix("podcasts.nowPlaying.") {
                result.elements[id] = element
            }
            // The expanded view keeps an inactive copy of the entire compact player.
            // Skip it so its stale metadata and controls cannot consume the scan budget.
            if id.hasPrefix("podcasts.miniPlayer.contentView["), id.contains("viewState=fullScreen") { continue }
            if insideMetadata && id.isEmpty && result.fallbackTitle.isEmpty {
                let description = text(element)
                if !description.isEmpty { result.fallbackTitle = description }
            }
            // On macOS 27.2 the compact container itself can be at depth 14.
            // Leave room for metadata descendants within the same node/time budgets.
            guard depth < 24, !id.hasPrefix("podcasts.shelf"), !id.hasPrefix("podcasts.tabBar"),
                  !id.hasPrefix("podcasts.listen["), !id.hasPrefix("podcasts.nowPlaying.queue") else { continue }
            let metadata = id.hasPrefix("podcasts.miniPlayer.metadataRegion[")
            let descendants = children(element).prefix(100).map { ($0, depth + 1, metadata) }
            if id.hasPrefix("podcasts.miniPlayer.contentView[") {
                // Reach the compact transport before retained expanded-view siblings.
                queue.insert(contentsOf: descendants, at: index)
            } else {
                queue.append(contentsOf: descendants)
            }
        }
        return result
    }
    /// Reads the active accessibility player and looks up local artwork using the episode and
    /// show metadata. Clears the cache if the app, permission, or player controls are missing.
    func read() async -> MusicSnapshot {
        let signposter = OSSignposter(subsystem: "dev.macmanager.MacManager", category: "PointsOfInterest")
        let interval = signposter.beginInterval("PodcastsRead", id: signposter.makeSignpostID())
        defer { signposter.endInterval("PodcastsRead", interval) }
        guard !Task.isCancelled else { return MusicSnapshot() }
        guard let app = application() else { releaseArtwork(); return MusicSnapshot(availability: .notRunning) }
        guard AXIsProcessTrusted() else { releaseArtwork(); return MusicSnapshot(availability: .accessibilityRequired) }
        let value = player(app)
        guard !Task.isCancelled else { return MusicSnapshot() }
        let nodes = value.elements
        guard let prefix = transportPrefix(value) else { releaseArtwork(); return MusicSnapshot(availability: .windowRequired) }
        var reading = PodcastPlayerReading()
        reading.title = text(nodes[prefix + "title"])
        reading.subtitle = text(nodes[prefix + "subtitle"])
        if prefix == "podcasts.nowPlaying." {
            reading.showTitle = reading.subtitle
            reading.expandedMetadata = text(nodes["podcasts.nowPlaying.eyebrow-podcasts.nowPlaying.title-podcasts.nowPlaying.subtitle"])
        }
        // Older versions expose only the mini-player title or a combined expanded label.
        if reading.title.isEmpty { reading.title = text(nodes["podcasts.miniPlayer.title"]) }
        if reading.title.isEmpty { reading.title = value.fallbackTitle }
        if reading.title.isEmpty { reading.title = reading.expandedMetadata }
        reading.playing = value.playerID.contains("isPlaying=true")
        reading.playbackControlLabel = text(nodes[prefix + "playbackTransportControl"])
        reading.elapsedText = timestamp(nodes[prefix + "playbackSlider.leadingTimestamp"])
        reading.remainingText = timestamp(nodes[prefix + "playbackSlider.trailingTimestamp"])
        reading.backwardLabel = text(nodes[prefix + "leadingTransportControl"])
        reading.forwardLabel = text(nodes[prefix + "trailingTransportControl"])
        if let slider = nodes[prefix + "playbackSlider"],
           let position = attribute(slider, kAXValueAttribute) as? NSNumber {
            let minimum = (attribute(slider, kAXMinValueAttribute) as? NSNumber)?.doubleValue ?? 0
            let maximum = (attribute(slider, kAXMaxValueAttribute) as? NSNumber)?.doubleValue ?? 1
            if maximum > minimum { reading.fraction = (position.doubleValue - minimum) / (maximum - minimum) }
        }
        var snapshot = reading.snapshot
        let key = ArtworkKey(title: reading.title, subtitle: reading.subtitle,
                             showTitle: reading.showTitle, expandedMetadata: reading.expandedMetadata)
        let now = ProcessInfo.processInfo.systemUptime
        if artworkKey != key || (cachedEpisode?.artwork == nil && now - artworkAttempt >= 30) {
            guard !Task.isCancelled else { return MusicSnapshot() }
            let local = await artworkAccess.read(title: key.title, expandedMetadata: key.expandedMetadata, showTitle: key.showTitle)
            guard !Task.isCancelled else { return MusicSnapshot() }
            artworkKey = key; artworkAttempt = now
            cachedEpisode = local.map {
                ($0.episodeTitle, $0.showTitle, $0.episodeID, $0.data.flatMap { ImageThumbnail.png($0) })
            }
        }
        guard !Task.isCancelled else { return MusicSnapshot() }
        if let cachedEpisode {
            snapshot.trackID = "podcast-" + cachedEpisode.id
            snapshot.title = cachedEpisode.title
            snapshot.artist = cachedEpisode.show
            snapshot.artwork = cachedEpisode.artwork
        }
        return snapshot
    }
    /// Resolves the player layout from transport controls that explicitly report themselves enabled.
    private func transportPrefix(_ player: Player) -> String? {
        let enabled = Set(player.elements.compactMap { identifier, element -> String? in
            guard identifier.hasSuffix("playbackTransportControl"),
                  (attribute(element, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { return nil }
            return identifier
        })
        return PodcastPlayerReading.transportPrefix(playerIdentifier: player.playerID, enabledIdentifiers: enabled)
    }
    /// Presses the requested transport button only while the player and the button are available.
    func perform(_ command: MusicCommand) async -> MusicAvailability {
        guard !Task.isCancelled, let app = application() else { return .notRunning }
        guard AXIsProcessTrusted() else { return .accessibilityRequired }
        let value = player(app)
        let suffix = switch command {
        case .playPause: "playbackTransportControl"
        case .previous: "leadingTransportControl"
        case .next: "trailingTransportControl"
        }
        guard !Task.isCancelled, let prefix = transportPrefix(value), let button = value.elements[prefix + suffix],
              (attribute(button, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { return .windowRequired }
        guard !Task.isCancelled else { return .idle }
        switch AXUIElementPerformAction(button, kAXPressAction as CFString) {
        case .success: return .ready
        case .cannotComplete: return .timedOut
        default: return .unavailable
        }
    }
    /// Prompts for accessibility access on the main actor unless the request was cancelled.
    func requestAccess() async -> MusicAvailability {
        await MainActor.run {
            guard !Task.isCancelled else { return .idle }
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options) ? .ready : .accessibilityRequired
        }
    }
    func releaseArtwork() { artworkKey = nil; artworkAttempt = 0; cachedEpisode = nil }

}
