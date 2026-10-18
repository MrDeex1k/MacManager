import AppKit
@preconcurrency import ApplicationServices
import QuartzCore
import MacManagerCore

/// Public Accessibility actions targeted at Podcasts, never global keys or private MediaRemote.
/// Reads only a bounded player subtree. A closed/unavailable window is reported explicitly.
actor ApplePodcastsAdapter: MusicPlayerAdapter {
    private let artworkAccess: PodcastArtworkAccess
    init(artworkAccess: PodcastArtworkAccess) { self.artworkAccess = artworkAccess }
    private var artworkKey: String?
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
            if id.hasPrefix("podcasts.miniPlayer.") || id.hasPrefix("podcasts.nowPlaying.") {
                result.elements[id] = element
            }
            if insideMetadata && id.isEmpty && result.fallbackTitle.isEmpty {
                let description = text(element)
                if !description.isEmpty { result.fallbackTitle = description }
            }
            guard depth < 9, !id.hasPrefix("podcasts.shelf"), !id.hasPrefix("podcasts.tabBar"),
                  !id.hasPrefix("podcasts.listen["), !id.hasPrefix("podcasts.nowPlaying.queue") else { continue }
            let metadata = id.hasPrefix("podcasts.miniPlayer.metadataRegion[")
            queue.append(contentsOf: children(element).prefix(100).map { ($0, depth + 1, metadata) })
        }
        return result
    }
    func read() async -> MusicSnapshot {
        guard !Task.isCancelled, let app = application() else { return MusicSnapshot(availability: .notRunning) }
        guard AXIsProcessTrusted() else { return MusicSnapshot(availability: .accessibilityRequired) }
        let value = player(app)
        guard !Task.isCancelled else { return MusicSnapshot() }
        let nodes = value.elements
        guard let prefix = transportPrefix(value) else { return MusicSnapshot(availability: .windowRequired) }
        var reading = PodcastPlayerReading()
        reading.title = text(nodes["podcasts.miniPlayer.title"])
        if reading.title.isEmpty { reading.title = value.fallbackTitle }
        reading.subtitle = text(nodes["podcasts.miniPlayer.subtitle"])
        reading.expandedMetadata = text(nodes["podcasts.nowPlaying.eyebrow-podcasts.nowPlaying.title-podcasts.nowPlaying.subtitle"])
        // In fully expanded mode Podcasts removes the mini-player title element.
        // Keep the exposed combined label verbatim rather than guessing comma boundaries.
        if reading.title.isEmpty { reading.title = reading.expandedMetadata }
        reading.playing = value.playerID.contains("isPlaying=true")
        reading.playbackControlLabel = text(nodes[prefix + "playbackTransportControl"])
        reading.elapsedText = text(nodes["podcasts.nowPlaying.playbackSlider.leadingTimestamp"])
        reading.remainingText = text(nodes["podcasts.nowPlaying.playbackSlider.trailingTimestamp"])
        reading.backwardLabel = text(nodes[prefix + "leadingTransportControl"])
        reading.forwardLabel = text(nodes[prefix + "trailingTransportControl"])
        if let slider = nodes[prefix + "playbackSlider"],
           let position = attribute(slider, kAXValueAttribute) as? NSNumber {
            let minimum = (attribute(slider, kAXMinValueAttribute) as? NSNumber)?.doubleValue ?? 0
            let maximum = (attribute(slider, kAXMaxValueAttribute) as? NSNumber)?.doubleValue ?? 1
            if maximum > minimum { reading.fraction = (position.doubleValue - minimum) / (maximum - minimum) }
        }
        var snapshot = reading.snapshot
        let key = reading.title + "\u{1f}" + reading.expandedMetadata
        let now = ProcessInfo.processInfo.systemUptime
        if artworkKey != key || (cachedEpisode?.artwork == nil && now - artworkAttempt >= 30) {
            artworkKey = key; artworkAttempt = now; cachedEpisode = nil
            if !Task.isCancelled, let local = await artworkAccess.read(title: reading.title, expandedMetadata: reading.expandedMetadata), !Task.isCancelled {
                cachedEpisode = (local.episodeTitle, local.showTitle, local.episodeID, local.data.flatMap { ImageThumbnail.png($0) })
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
    private func transportPrefix(_ player: Player) -> String? {
        for prefix in ["podcasts.miniPlayer.", "podcasts.nowPlaying."] {
            if player.elements[prefix + "playbackTransportControl"] != nil { return prefix }
        }
        return nil
    }
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
              (attribute(button, kAXEnabledAttribute) as? NSNumber)?.boolValue != false else { return .windowRequired }
        switch AXUIElementPerformAction(button, kAXPressAction as CFString) {
        case .success: return .ready
        case .cannotComplete: return .timedOut
        default: return .unavailable
        }
    }
    func requestAccess() async -> MusicAvailability {
        await MainActor.run {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options) ? .ready : .accessibilityRequired
        }
    }
    func releaseArtwork() { artworkKey = nil; artworkAttempt = 0; cachedEpisode = nil }

}
