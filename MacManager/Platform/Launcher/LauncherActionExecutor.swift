import AppKit
import MacManagerCore

/// Framework effects live here; the controller retains presentation and focus policy.
@MainActor final class LauncherActionExecutor {
    enum Outcome { case copied, opened, section(String), failed }
    private let writer: LocalClipboardWriter
    init(testing: Bool) {
        var testName = "MacManagerLauncherTests-\(UUID().uuidString)"
        #if DEBUG
        if testing, UITestConfiguration.current.enabled,
           let name = ProcessInfo.processInfo.environment["MM_LAUNCHER_TEST_PASTEBOARD"],
           name.hasPrefix("MacManagerLauncherTests-") { testName = name }
        #endif
        writer = LocalClipboardWriter(pasteboard: testing
            ? NSPasteboard(name: .init(testName)) : .general)
    }
    func execute(_ entry: LauncherEntry, options: LauncherPreferences, clipboard: ClipboardService?) async -> Outcome {
        switch entry.action {
        case .clipboard(let id):
            guard let clipboard, !clipboard.suspended else { return .failed }
            return await clipboard.restore(id) ? .copied : .failed
        case .copy(let text):
            do {
                // A calculator result is a new copy; only history restores carry exclusion markers.
                try writer.writeText(text, history: .allowCapture)
                return .copied
            } catch { return .failed }
        case .file(let url):
            guard options.filesEnabled, LauncherFileSearch.isWithinRoots(url, roots: options.folders),
                  NSWorkspace.shared.open(url) else { return .failed }
            return .opened
        case .section(let section): return .section(section)
        case .systemSettings(let url):
            guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return .failed }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let opened: Bool = await withCheckedContinuation { continuation in
                NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration) { _, error in
                    continuation.resume(returning: error == nil)
                }
            }
            return opened ? .opened : .failed
        case .application(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { return .failed }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            // A selected installation must not resolve to another running copy with the same bundle ID.
            configuration.allowsRunningApplicationSubstitution = false
            let opened: Bool = await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                    continuation.resume(returning: error == nil)
                }
            }
            return opened ? .opened : .failed
        }
    }
}
