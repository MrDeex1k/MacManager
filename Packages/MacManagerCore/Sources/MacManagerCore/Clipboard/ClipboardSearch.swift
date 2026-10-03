import Foundation
import OSLog

/// Snapshots are held only for the duration of a search, never cached by this actor.
public actor ClipboardSearch {
    private let signposter = OSSignposter(subsystem: "dev.macmanager.MacManager", category: "clipboard-search")
    public init() {}

    public func search(_ query: String, entries: [ClipboardEntry], limit: Int = 1_000) throws -> [ClipboardEntry] {
        let interval = signposter.beginInterval("Filter", id: signposter.makeSignpostID())
        defer { signposter.endInterval("Filter", interval) }
        guard limit > 0 else { return [] }
        var result: [ClipboardEntry] = []
        for entry in entries {
            try Task.checkCancellation()
            guard !entry.damaged, query.isEmpty || entry.text?.localizedStandardContains(query) == true else { continue }
            result.append(entry)
            if result.count == limit { break }
        }
        try Task.checkCancellation()
        return result
    }
}
