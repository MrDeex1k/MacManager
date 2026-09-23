// Adapted from Tinycast HotKeyCenter, Copyright (C) 2026 Abue Ammar.
// AGPL-3.0-or-later; used under AGPL-3.0. Source: c5cff8cbb9b7e12ac75c058da9573045c76029b7.
// Modified 2026-09-23: one binding, transactional replacement, explicit conflict state and teardown.
import Carbon.HIToolbox
import MacManagerCore

private func launcherHotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let result = GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard result == noErr else { return result }
    let owner = Unmanaged<LauncherHotKey>.fromOpaque(context).takeUnretainedValue()
    return MainActor.assumeIsolated { owner.handle(id) }
}

@MainActor final class LauncherHotKey {
    private var handler: EventHandlerRef?
    private var registration: EventHotKeyRef?
    private var current: LauncherShortcut?
    private var sequence: UInt32 = 0
    private let signature: OSType = 0x4D4D4C52
    var onPress: (() -> Void)?

    func register(_ shortcut: LauncherShortcut) -> Bool {
        guard shortcut.isValid else { return false }
        if !shortcut.enabled { stop(); return true }
        if current == shortcut, registration != nil { return true }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            guard InstallEventHandler(GetEventDispatcherTarget(), launcherHotKeyHandler, 1, &type,
                Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr else { return false }
        }
        var newRegistration: EventHotKeyRef?
        let newID = sequence &+ 1
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: signature, id: newID), GetEventDispatcherTarget(), 0, &newRegistration) == noErr,
              let newRegistration else { return false }
        if let registration { UnregisterEventHotKey(registration) }
        registration = newRegistration; current = shortcut; sequence = newID
        return true
    }
    func stop() {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
        registration = nil; handler = nil; current = nil
    }
    fileprivate func handle(_ id: EventHotKeyID) -> OSStatus {
        guard id.signature == signature, id.id == sequence, registration != nil else { return OSStatus(eventNotHandledErr) }
        onPress?()
        return noErr
    }
}
