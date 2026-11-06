import Foundation

/// Recover independently valid fields without treating damaged saved settings as a fresh install.
enum PreferenceRecovery {
    static func load<Value: Codable>(_ stored: Any?, defaults: Value, safe: Value,
                                     isValid: (Value) -> Bool = { _ in true }) -> (value: Value, recovered: Bool) {
        guard let stored else { return (defaults, false) }
        let decoder = JSONDecoder()
        if let data = stored as? Data, let value = try? decoder.decode(Value.self, from: data), isValid(value) {
            return (value, false)
        }
        guard let data = stored as? Data,
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseline = try? JSONEncoder().encode(safe),
              var fields = try? JSONSerialization.jsonObject(with: baseline) as? [String: Any] else {
            return (safe, true)
        }
        func decode(_ candidate: [String: Any]) -> Value? {
            guard let bytes = try? JSONSerialization.data(withJSONObject: candidate),
                  let value = try? decoder.decode(Value.self, from: bytes), isValid(value) else { return nil }
            return value
        }
        for key in saved.keys.sorted() where fields[key] != nil {
            var candidate = fields
            candidate[key] = saved[key]
            if decode(candidate) != nil { fields = candidate }
            else if key == "items", let items = saved[key] as? [String: Any] {
                // A damaged launcher entry must not discard unrelated aliases and favorites.
                var validItems: [String: Any] = [:]
                for id in items.keys.sorted() {
                    var trial = validItems; trial[id] = items[id]
                    candidate = fields; candidate[key] = trial
                    if decode(candidate) != nil { validItems = trial; fields = candidate }
                }
            }
        }
        // Unknown exclusions must never silently become an empty allow-all policy.
        if fields["excludedBundleIDs"] != nil,
           saved["excludedBundleIDs"] != nil, !(saved["excludedBundleIDs"] is [String]) {
            fields["enabled"] = false; fields["paused"] = true
        }
        return (decode(fields) ?? safe, true)
    }
}
