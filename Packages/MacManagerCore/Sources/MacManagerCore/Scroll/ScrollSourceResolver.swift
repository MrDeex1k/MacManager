import CoreGraphics
import Foundation
import MMInput

/// Event provenance is separate from scroll continuity: a smooth mouse is still a mouse.
public enum ScrollOrigin: Equatable, Sendable {
    case device(UInt64)
    case application
    case unidentified

    public init(event: CGEvent) {
        let origin = mm_scroll_event_origin(event)
        self.init(hidInspectionAvailable: origin.hid_inspection_available, hasHID: origin.has_hid,
                  senderID: origin.sender_id, sourcePID: origin.source_pid)
    }

    init(hidInspectionAvailable: Bool, hasHID: Bool, senderID: UInt64, sourcePID: Int64) {
        if hasHID {
            self = senderID != 0 ? .device(senderID) : .unidentified
        } else if hidInspectionAvailable && sourcePID > 0 && sourcePID <= Int32.max {
            self = .application
        } else {
            self = .unidentified
        }
    }
}

/// The lock owns cache/pending/lifecycle state. Registry lookups run on a serial queue,
/// outside the event callback and the lock. Results from a stopped/reset session are ignored.
public final class ScrollSourceResolver: @unchecked Sendable {
    private struct Entry {
        let source: ScrollSource
        let expires: TimeInterval
        var lastUsed: TimeInterval
    }
    private let lock = NSLock()
    private let queue: DispatchQueue
    private let lookup: @Sendable (UInt64) -> ScrollSource
    private let capacity: Int
    private let maximumPending: Int
    private var cache: [UInt64: Entry] = [:]
    private var pending: Set<UInt64> = []
    private var generation: UInt64 = 0
    private var active = true

    public convenience init() {
        self.init(lookup: { sender in
            switch mm_scroll_local_device_kind(sender) {
            case MMScrollDeviceMouse: .mouse
            case MMScrollDeviceTrackpad: .trackpad
            default: .unknown
            }
        })
    }

    init(capacity: Int = 64, maximumPending: Int = 4,
         queue: DispatchQueue = DispatchQueue(label: "dev.macmanager.scroll-device-lookup", qos: .utility),
         lookup: @escaping @Sendable (UInt64) -> ScrollSource) {
        self.capacity = max(1, min(64, capacity))
        self.maximumPending = max(1, min(4, maximumPending))
        self.queue = queue
        self.lookup = lookup
    }

    /// A nil result requests the existing gesture classifier. A posting process alone
    /// cannot distinguish automation from wheel events reconstructed by a mouse driver.
    public func resolve(_ origin: ScrollOrigin, at now: TimeInterval) -> ScrollSource? {
        guard case .device(let sender) = origin, sender != 0, now.isFinite, now >= 0 else { return nil }
        return lock.withLock {
            guard active else { return nil }
            if var entry = cache[sender], now < entry.expires, now >= entry.lastUsed {
                entry.lastUsed = now
                cache[sender] = entry
                return entry.source == .unknown ? nil : entry.source
            }
            guard !pending.contains(sender), pending.count < maximumPending else { return nil }
            pending.insert(sender)
            let token = generation
            queue.async { [weak self] in
                guard let self, self.lock.withLock({ self.active && self.generation == token }) else { return }
                let detected = self.lookup(sender)
                let source: ScrollSource = detected == .mouse || detected == .trackpad ? detected : .unknown
                self.lock.withLock {
                    guard self.active, self.generation == token else { return }
                    self.pending.remove(sender)
                    if self.cache[sender] == nil, self.cache.count >= self.capacity,
                       let oldest = self.cache.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
                        self.cache.removeValue(forKey: oldest)
                    }
                    // Revalidate successes after 30 s; retry unresolved services at most once/s.
                    self.cache[sender] = Entry(source: source, expires: now + (source == .unknown ? 1 : 30), lastUsed: now)
                }
            }
            return nil
        }
    }

    public func reset() {
        lock.withLock { generation &+= 1; cache.removeAll(); pending.removeAll() }
    }

    public func stop() {
        lock.withLock { active = false; generation &+= 1; cache.removeAll(); pending.removeAll() }
    }

    var cachedDeviceCount: Int { lock.withLock { cache.count } }
    var pendingDeviceCount: Int { lock.withLock { pending.count } }
}
