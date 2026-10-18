#!/bin/sh
# Exercise process-local notifications, never lock, sleep or switch the real session.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workspace=$(mktemp -d "${TMPDIR:-/tmp}/macmanager-session-tests.XXXXXX")
trap 'rm -rf "$workspace"' EXIT HUP INT TERM
cat "$root/Packages/MacManagerCore/Sources/MacManagerCore/ApplicationLifecycleCoordinator.swift" \
    "$root/Packages/MacManagerCore/Sources/MacManagerCore/SessionState.swift" \
    "$root/MacManager/Platform/Application/NotificationTokens.swift" > "$workspace/Support.swift"
sed '/^import MacManagerCore$/d' "$root/MacManager/Platform/Application/SystemSessionMonitor.swift" >> "$workspace/Support.swift"
cat > "$workspace/main.swift" <<'SWIFT'
import AppKit
MainActor.assumeIsolated {
    let monitor = SystemSessionMonitor()
    let tokens = NotificationTokens()
    var values: [SessionState] = []
    monitor.start(); monitor.start()
    monitor.subscribe(in: tokens) { values.append($0) }
    let center = NSWorkspace.shared.notificationCenter
    center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    assert(values.last?.suspended == true)
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    assert(values.last?.sleeping == true)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    assert(values.last?.sleeping == false && values.last?.suspended == true)
    center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    assert(values.count == 5, "Each transition must publish once")
    let count = values.count
    monitor.stop()
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    assert(values.count == count, "Stopped monitor must release its registrations")
    monitor.start(); monitor.start()
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    assert(values.count == count + 1 && values.last?.sleeping == true, "Restart must register once")
    monitor.stop()
    tokens.removeAll()
    print("Session monitor notifications and teardown: PASS")
}
SWIFT
swiftc "$workspace/Support.swift" "$workspace/main.swift" -o "$workspace/session-tests"
"$workspace/session-tests"
