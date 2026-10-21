import AppKit
import MacManagerCore

/// Framework effects live here; the controller retains presentation and focus policy.
@MainActor final class LauncherActionExecutor {
    enum Outcome { case copied, opened, section(String), failed }
    private let pasteboard: SystemClipboardPasteboard
    init(testing: Bool) {
        pasteboard = SystemClipboardPasteboard(pasteboard: testing
            ? NSPasteboard(name: .init("MacManagerLauncherTests-\(UUID().uuidString)")) : .general)
    }
    func execute(_ entry: LauncherEntry, options: LauncherPreferences, clipboard: ClipboardService?) async -> Outcome {
        switch entry.action {
        case .clipboard(let id):
            guard let clipboard, !clipboard.suspended else { return .failed }
            return await clipboard.restore(id) ? .copied : .failed
        case .copy(let text):
            do {
                try pasteboard.restore(.init(kind: .text, data: Data(text.utf8)))
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
            let opened: Bool = await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                    continuation.resume(returning: error == nil)
                }
            }
            return opened ? .opened : .failed
        }
    }
}
