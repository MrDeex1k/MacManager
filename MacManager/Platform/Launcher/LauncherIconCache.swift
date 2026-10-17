import AppKit

@MainActor final class LauncherIconCache {
    private let images = NSCache<NSURL, NSImage>()
    private var refreshedAt: ContinuousClock.Instant?
    init() { images.countLimit = 128 }
    func refreshIfNeeded(after seconds: Double) {
        if refreshedAt.map({ $0.duration(to: .now) >= .seconds(seconds) }) ?? true {
            clear(); refreshedAt = .now
        }
    }
    func image(at url: URL) -> NSImage {
        if let image = images.object(forKey: url as NSURL) { return image }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        images.setObject(image, forKey: url as NSURL)
        return image
    }
    func remove(_ url: URL) { images.removeObject(forKey: url as NSURL) }
    func clear() { images.removeAllObjects(); refreshedAt = nil }
}
