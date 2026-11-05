import Foundation
import Observation

public enum MusicAvailability: String, Sendable { case idle, ready, notRunning, needsPermission, denied, timedOut, unavailable, accessibilityRequired, windowRequired }
public enum MusicPlayback: Equatable, Sendable { case stopped, paused, playing }
public enum MusicCommand: Equatable, Sendable { case playPause, previous, next }

public struct MusicSnapshot: Sendable {
    public var availability: MusicAvailability
    public var playback: MusicPlayback
    public var trackID: String?
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double?
    public var position: Double?
    public var progressFraction: Double?
    public var previousLabel: String?
    public var nextLabel: String?
    public var artwork: Data?
    public init(availability: MusicAvailability = .idle, playback: MusicPlayback = .stopped,
                trackID: String? = nil, title: String = "", artist: String = "", album: String = "",
                duration: Double? = nil, position: Double? = nil, artwork: Data? = nil,
                progressFraction: Double? = nil, previousLabel: String? = nil, nextLabel: String? = nil) {
        self.availability = availability; self.playback = playback; self.trackID = trackID
        self.title = title; self.artist = artist; self.album = album
        let validDuration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.duration = validDuration
        self.position = position.flatMap { $0.isFinite ? max(0, min($0, validDuration ?? $0)) : nil }
        self.progressFraction = progressFraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
        self.previousLabel = previousLabel; self.nextLabel = nextLabel
        self.artwork = artwork
    }
}

public protocol MusicPlayerAdapter: Sendable {
    func read() async -> MusicSnapshot
    func perform(_ command: MusicCommand) async -> MusicAvailability
    func requestAccess() async -> MusicAvailability
    func releaseArtwork() async
}

/// One shared player service; all periodic work belongs to the visible music surface.
@MainActor @Observable public final class MusicService {
    public private(set) var snapshot = MusicSnapshot()
    public private(set) var visible = false
    public private(set) var busy = false
    public private(set) var commandFailed = false
    @ObservationIgnored private let adapter: any MusicPlayerAdapter
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var action: Task<Void, Never>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    public var hasPendingWork: Bool { loop != nil || action != nil }

    public init(adapter: any MusicPlayerAdapter) { self.adapter = adapter }
    /// Starts reading when visible; hiding clears presentation and releases cached private data.
    public func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value; generation += 1
        let previousLoop = loop, previousAction = action
        loop?.cancel(); loop = nil; action?.cancel(); action = nil; busy = false; commandFailed = false
        if value {
            startLoop(waitingFor: previousLoop)
        } else {
            snapshot = MusicSnapshot()
            let previousCleanup = cleanup, adapter = adapter
            cleanup = Task {
                await previousCleanup?.value
                await previousLoop?.value
                await previousAction?.value
                await adapter.releaseArtwork()
            }
        }
    }
    private func startLoop(waitingFor previousLoop: Task<Void, Never>? = nil, readImmediately: Bool = true) {
        let token = generation, previousCleanup = cleanup
        loop = Task { [weak self] in
            // A cancelled synchronous player read can still be finishing. Do not overlap it
            // or bypass the cache cleanup from an earlier visibility cycle.
            await previousLoop?.value
            await previousCleanup?.value
            guard let self, !Task.isCancelled, self.visible, token == self.generation else { return }
            if readImmediately { await self.refresh(token: token) }
            while !Task.isCancelled, self.visible, token == self.generation {
                let seconds = self.snapshot.availability == .idle ||
                    (self.snapshot.availability == .ready && self.snapshot.playback == .playing) ? 1 : 3
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                await self.refresh(token: token)
            }
        }
    }
    private func refresh(token: Int) async {
        guard !Task.isCancelled, visible, token == generation else { return }
        let value = await adapter.read()
        guard !Task.isCancelled, visible, token == generation else { return }
        snapshot = value
    }
    /// Re-reads a visible player while preserving its snapshot and adapter artwork cache.
    public func refresh() {
        guard visible, !busy else { return }
        generation += 1; commandFailed = false
        let previousLoop = loop
        previousLoop?.cancel()
        startLoop(waitingFor: previousLoop)
    }
    public func perform(_ command: MusicCommand) {
        guard visible, !busy, snapshot.availability == .ready else { return }
        execute { await $0.perform(command) }
    }
    public func requestAccess() {
        guard visible, !busy else { return }
        execute { await $0.requestAccess() }
    }
    private func execute(_ operation: @escaping @Sendable (any MusicPlayerAdapter) async -> MusicAvailability) {
        busy = true; commandFailed = false
        let previousLoop = loop
        previousLoop?.cancel()
        loop = nil
        let token = generation
        action = Task { [weak self] in
            // The adapter can suspend during a read. Drain it before issuing a command
            // so obsolete metadata cannot race the post-command refresh.
            await previousLoop?.value
            guard let self, !Task.isCancelled, self.visible, token == self.generation else { return }
            let result = await operation(self.adapter)
            guard !Task.isCancelled, self.visible, token == self.generation else { return }
            self.commandFailed = result != .ready
            if result == .ready { await self.refresh(token: token) }
            else { self.snapshot = MusicSnapshot(availability: result) }
            guard !Task.isCancelled, self.visible, token == self.generation else { return }
            self.busy = false; self.action = nil
            self.startLoop(readImmediately: false)
        }
    }
}
