import Foundation

// Shared by payloads and thumbnails, confined to ClipboardRepository's actor.
struct ClipboardMemoryCache {
    struct Key: Hashable { let id: UUID; let role: String }
    private struct Value { let data: Data; var used: UInt64 }
    let limit: Int
    private var values: [Key: Value] = [:]
    private var clock: UInt64 = 0
    private(set) var bytes = 0

    mutating func value(for key: Key) -> Data? {
        guard var value = values[key] else { return nil }
        clock &+= 1; value.used = clock; values[key] = value
        return value.data
    }
    mutating func insert(_ data: Data, for key: Key) {
        guard data.count <= limit, limit > 0 else { return }
        if let old = values.removeValue(forKey: key) { bytes -= old.data.count }
        while bytes + data.count > limit, let oldest = values.min(by: { $0.value.used < $1.value.used })?.key {
            bytes -= values.removeValue(forKey: oldest)!.data.count
        }
        clock &+= 1
        values[key] = Value(data: data, used: clock); bytes += data.count
    }
    mutating func remove(_ ids: Set<UUID>) {
        for key in Array(values.keys) where ids.contains(key.id) {
            bytes -= values.removeValue(forKey: key)!.data.count
        }
    }
    mutating func clear() { values.removeAll(); bytes = 0 }
}
