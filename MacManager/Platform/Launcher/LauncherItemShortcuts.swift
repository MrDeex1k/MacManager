import MacManagerCore

/// Owns OS registrations; personalization/conflict policy stays in the controller.
@MainActor final class LauncherItemShortcuts {
    private var bindings: [String: LauncherHotKey] = [:]
    func register(id: String, shortcut: LauncherShortcut, enabled: Bool, action: @escaping () -> Void) -> Bool {
        let binding = bindings[id] ?? LauncherHotKey()
        guard !enabled || binding.register(shortcut) else {
            if bindings[id] == nil { binding.stop() }
            return false
        }
        binding.onPress = action
        bindings[id] = binding
        return true
    }
    func remove(_ id: String) { bindings.removeValue(forKey: id)?.stop() }
    func stop() { bindings.values.forEach { $0.stop() }; bindings.removeAll() }
}
