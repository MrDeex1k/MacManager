import AppKit
import MacManagerCore
import Observation
import SwiftUI

@MainActor @Observable
final class LauncherController: ApplicationLifecycleParticipant {
    let model = LauncherSearchModel()
    var clipboard: ClipboardService?
    private(set) var clipboardMode = false
    var fileFilter = LauncherFileFilter.all
    var customizationEntry: LauncherEntry?
    var options: LauncherPreferences { preferences.launcher }
    var showsResults: Bool { clipboardMode || !model.query.isEmpty }
    @ObservationIgnored private let files = LauncherFileSearch()
    @ObservationIgnored private let clipboardSearch = ClipboardSearch()
    @ObservationIgnored private let applicationIcons = NSCache<NSURL, NSImage>()
    @ObservationIgnored private let thumbnails = NSCache<NSUUID, NSImage>()
    @ObservationIgnored private var shortcutCleanup: Task<Void, Never>?
    @ObservationIgnored private var lastIconRefresh: ContinuousClock.Instant?

    @ObservationIgnored private var itemHotKeys: [String: LauncherHotKey] = [:]
    private(set) var itemShortcutFailures: Set<String> = []
    private(set) var shortcutFailed = false
    private(set) var actionFailed = false
    private(set) var visible = false
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored var navigate: ((String) -> Void)?
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let resultPasteboard: SystemClipboardPasteboard
    @ObservationIgnored private let hotKey = LauncherHotKey()
    @ObservationIgnored private var panel: LauncherPanel?
    @ObservationIgnored private var hosting: NSHostingView<AnyView>?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private let testing: Bool
    private var usesRealShortcut: Bool { !testing || ProcessInfo.processInfo.arguments.contains("--launcher-live-testing") }
    @ObservationIgnored private var running = false
    @ObservationIgnored private var presentationID = UUID()
    private(set) var executing = false
    var strings: AppStrings { AppStrings(languageCode: preferences.language.resolvedCode()) }

    init(preferences: PreferencesStore, testing: Bool = false) {
        self.preferences = preferences; self.testing = testing
        resultPasteboard = SystemClipboardPasteboard(pasteboard: testing
            ? NSPasteboard(name: .init("MacManagerLauncherTests-\(UUID().uuidString)")) : .general)
    }
    func start() {
        guard !running else { return }; running = true
        hotKey.onPress = { [weak self] in self?.toggle() }
        if usesRealShortcut { shortcutFailed = !hotKey.register(preferences.launcherShortcut) }
        model.additionalResults = { [weak self] query in
            guard let self, self.visible else { return [] }
            if self.clipboardMode {
                guard let clipboard = self.clipboard, !clipboard.suspended else { return [] }
                let entries = try await self.clipboardSearch.search(query, entries: clipboard.entries, limit: 40)
                try Task.checkCancellation()
                guard self.visible, self.clipboardMode, !clipboard.suspended else { return [] }
                return entries.map {
                        LauncherEntry(id: "clipboard:" + $0.id.uuidString,
                            title: $0.text.map { String($0.prefix(200)) } ?? self.strings("clipboard.image"),
                            subtitle: self.strings("clipboard.restore"), symbol: $0.record.kind == .text ? "doc.plaintext" : "photo",
                            action: .clipboard($0.id))
                    }
            }
            var results = LocalCalculator.result(query, language: self.preferences.language.resolvedCode()).map { [$0] } ?? []
            let options = self.preferences.launcher, filter = self.fileFilter
            if results.isEmpty && options.filesEnabled && query.count >= 2 {
                try await Task.sleep(for: .milliseconds(120))
                results += try await self.files.search(query, roots: options.folders, filter: filter)
            }
            return results
        }
        registerItemShortcuts()
        reconcileApplicationShortcuts()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification)
        observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsLocked"))
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(restoreFocus: false) }
        }
        observers.append((center, token))
    }
    func stop() {
        running = false; hide(restoreFocus: false); hotKey.stop()
        model.cancel(); shortcutCleanup?.cancel(); shortcutCleanup = nil
        applicationIcons.removeAllObjects()
        panel?.contentView = nil; hosting = nil
        itemHotKeys.values.forEach { $0.stop() }; itemHotKeys = [:]
        observers.forEach { $0.0.removeObserver($0.1) }; observers = []
    }
    @discardableResult func updateShortcut(_ value: LauncherShortcut) -> Bool {
        guard value.isValid else { return false }
        if value.enabled && preferences.launcher.items.values.contains(where: {
            $0.shortcut?.enabled == true && $0.shortcut?.keyCode == value.keyCode && $0.shortcut?.modifiers == value.modifiers
        }) { shortcutFailed = true; return false }
        let success = !usesRealShortcut || hotKey.register(value)
        shortcutFailed = !success
        if success { preferences.launcherShortcut = value }
        return success
    }
    func toggle() { visible ? hide() : show() }
    func show() {
        guard running else { return }
        if visible { panel?.makeKeyAndOrderFront(nil); return }
        reconcileApplicationShortcuts()
        if lastIconRefresh.map({ $0.duration(to: .now) >= .seconds(60) }) ?? true {
            applicationIcons.removeAllObjects()
            lastIconRefresh = .now
        }
        previousApplication = NSWorkspace.shared.frontmostApplication
        actionFailed = false; executing = false; presentationID = UUID()
        let commands = AppSection.allCases.map { section in
            LauncherEntry(id: "command:" + section.rawValue, title: strings(section.titleKey),
                subtitle: "Mac Manager", symbol: section.symbol, action: .section(section.rawValue),
                alternateNames: [AppStrings(languageCode: "en")(section.titleKey), AppStrings(languageCode: "pl")(section.titleKey)])
        }
        model.preferences = preferences.launcher
        model.load(providers: testing && !usesRealShortcut ? [] : [ApplicationProvider(), SystemSettingsProvider()],
                   language: preferences.language.resolvedCode(), commands: commands)
        let panel = self.panel ?? LauncherPanel()
        self.panel = panel
        panel.onEscape = { [weak self] in
            guard let self else { return }
            if self.model.query.isEmpty { self.hide() } else { self.model.search("") }
        }
        panel.navigationEnabled = { [weak self] in self?.customizationEntry == nil }
        panel.onTab = { [weak self] in self?.toggleMode() }
        panel.onArrow = { [weak self] in self?.model.moveSelection($0) }
        panel.onSubmit = { [weak self] in self?.performSelected() }
        panel.onResign = { [weak self] in if self?.customizationEntry == nil { self?.hide(restoreFocus: false) } }
        let root = AnyView(LauncherView(controller: self)
            .environment(\.locale, preferences.locale).preferredColorScheme(.dark).tint(AppTheme.accent))
        let hosting = self.hosting ?? NSHostingView(rootView: root)
        hosting.rootView = root
        hosting.sizingOptions = []
        self.hosting = hosting
        if panel.contentView !== hosting { panel.contentView = hosting }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let width = min(680.0, frame.width - 40)
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.maxY - min(160, frame.height / 5) - 90,
                              width: width, height: 90), display: false)
        visible = true
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.visible else { return }
            self.panel?.focusSearchField()
        }
    }
    func toggleMode(clipboard: Bool? = nil) {
        clipboardMode = clipboard ?? !clipboardMode
        model.onlyAdditionalResults = clipboardMode
        model.search("")
        resize(rowCount: model.results.count)
    }
    func refreshResults() {
        model.preferences = preferences.launcher
        model.search(model.query)
    }
    func updateOptions(_ value: LauncherPreferences) {
        preferences.launcher = value
        refreshResults()
    }
    func canCustomize(_ entry: LauncherEntry) -> Bool {
        switch entry.action { case .application, .section, .systemSettings: true; default: false }
    }
    @discardableResult func saveCustomization(_ value: LauncherCustomization) -> Bool {
        guard registerCustomization(value) else { return false }
        var bounded = value; bounded.alias = String(value.alias.prefix(100))
        preferences.launcher.items[value.entry.id] = bounded
        refreshResults()
        return true
    }

    private func registerCustomization(_ value: LauncherCustomization) -> Bool {
        guard canCustomize(value.entry) else { return false }
        let id = value.entry.id
        if let shortcut = value.shortcut, shortcut.enabled {
            let palette = preferences.launcherShortcut
            let duplicate = palette.enabled && palette.keyCode == shortcut.keyCode && palette.modifiers == shortcut.modifiers
                || preferences.launcher.items.contains { key, item in
                    key != id && item.shortcut?.enabled == true && item.shortcut?.keyCode == shortcut.keyCode && item.shortcut?.modifiers == shortcut.modifiers
                }
            guard !duplicate, shortcut.isValid else { itemShortcutFailures.insert(id); return false }
            let binding = itemHotKeys[id] ?? LauncherHotKey()
            guard !usesRealShortcut || binding.register(shortcut) else {
                if itemHotKeys[id] == nil { binding.stop() }; itemShortcutFailures.insert(id); return false
            }
            binding.onPress = { [weak self] in self?.execute(value.entry) }
            itemHotKeys[id] = binding
        } else { itemHotKeys.removeValue(forKey: id)?.stop() }
        itemShortcutFailures.remove(id)
        return true
    }
    func removeCustomization(_ id: String) {
        itemHotKeys.removeValue(forKey: id)?.stop()
        preferences.launcher.items.removeValue(forKey: id)
        itemShortcutFailures.remove(id)
        refreshResults()
    }
    private func registerItemShortcuts() {
        for value in preferences.launcher.items.values { _ = registerCustomization(value) }
    }

    func applicationIcon(at url: URL) -> NSImage {
        if let image = applicationIcons.object(forKey: url as NSURL) { return image }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        applicationIcons.countLimit = 128
        applicationIcons.setObject(image, forKey: url as NSURL)
        return image
    }

    func thumbnail(for id: UUID, data: Data) -> NSImage? {
        if let image = thumbnails.object(forKey: id as NSUUID) { return image }
        guard let image = NSImage(data: data) else { return nil }
        thumbnails.countLimit = 40
        thumbnails.setObject(image, forKey: id as NSUUID)
        return image
    }

    func invalidateThumbnails() { thumbnails.removeAllObjects() }

    private func reconcileApplicationShortcuts() {
        guard shortcutCleanup == nil else { return }
        let saved = preferences.launcher.items
        let candidates = saved.values.filter {
            if case .application = $0.entry.action { return $0.shortcut != nil }
            return false
        }
        guard !candidates.isEmpty else { return }
        shortcutCleanup = Task { [weak self] in
            let scan = Task.detached(priority: .utility) {
                candidates.filter { item in
                    if case .application(let url) = item.entry.action {
                        guard !Task.isCancelled else { return false }
                        let parts = url.pathComponents
                        if parts.count > 2, parts[1] == "Volumes",
                           !FileManager.default.fileExists(atPath: "/Volumes/" + parts[2]) { return false }
                        return !FileManager.default.fileExists(atPath: url.path)
                    }
                    return false
                }
            }
            let missing = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
            guard let self, self.running, !Task.isCancelled else { return }
            defer { self.shortcutCleanup = nil }
            var updated = self.preferences.launcher
            var replacements: [String: LauncherEntry] = [:]
            var removed = Set<String>()
            for item in missing where updated.items[item.entry.id] == item {
                // An app outside our scan scopes, or moved to another folder, is not deleted.
                let bundleID = item.entry.bundleID ?? String(item.entry.id.dropFirst("app:".count))
                let replacement = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                let installed = replacement.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                updated.reconcileApplication(id: item.entry.id, installedURL: installed)
                if installed == nil { removed.insert(item.entry.id) }
                else { replacements[item.entry.id] = updated.items[item.entry.id]?.entry }
                self.itemHotKeys.removeValue(forKey: item.entry.id)?.stop()
                self.itemShortcutFailures.remove(item.entry.id)
                if let value = updated.items[item.entry.id], installed != nil { _ = self.registerCustomization(value) }
            }
            if updated != self.preferences.launcher {
                self.preferences.launcher = updated
                self.model.reconcileApplications(replacements: replacements, removed: removed)
                if self.visible { self.refreshResults() }
            }
        }
    }

    func resize(rowCount: Int) {
        guard visible, let panel else { return }
        // A stable results area avoids resizing the window for each intermediate query.
        let height: CGFloat = !showsResults ? 90 : 90 + 7 * 56 + 32
        var frame = panel.frame
        let available = panel.screen?.visibleFrame ?? frame
        let bounded = min(height, available.height - 40)
        frame.origin.y += frame.height - bounded; frame.size.height = bounded
        frame.origin.y = max(frame.origin.y, available.minY + 20)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true, animate: false)
    }
    func hide(restoreFocus: Bool = true) {
        guard visible else { return }
        visible = false; presentationID = UUID(); executing = false
        panel?.orderOut(nil)
        // Reuse the host, but release the private mode's SwiftUI subtree immediately.
        if clipboardMode { hosting?.rootView = AnyView(Color.clear) }
        thumbnails.removeAllObjects()
        model.cancel(); model.onlyAdditionalResults = false; clipboardMode = false; customizationEntry = nil; actionFailed = false
        if restoreFocus, let previousApplication, !previousApplication.isTerminated,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate()
        }
        previousApplication = nil
    }
    func performSelected() { if showsResults, let entry = model.selected { perform(entry) } }
    func perform(_ entry: LauncherEntry) {
        guard visible, !executing, model.canPerform(entry) else { return }
        execute(entry)
    }
    private func execute(_ entry: LauncherEntry) {
        switch entry.action {
        case .clipboard(let id):
            guard let clipboard, !clipboard.suspended else { return }
            let token = presentationID
            executing = true
            Task {
                await clipboard.restore(id)
                guard token == presentationID else { return }
                executing = false
                if clipboard.failure == nil { hide() } else { actionFailed = true }
            }
        case .copy(let text):
            do {
                try resultPasteboard.restore(ClipboardRestoredContent(kind: .text, data: Data(text.utf8)))
                hide()
            } catch { actionFailed = true }
        case .file(let url):
            guard preferences.launcher.filesEnabled,
                  LauncherFileSearch.isWithinRoots(url, roots: preferences.launcher.folders),
                  NSWorkspace.shared.open(url) else { actionFailed = true; return }
            hide(restoreFocus: false)
        case .section(let section):
            if section == "clipboard" { if !visible { show() }; toggleMode(clipboard: true); return }
            hide(restoreFocus: false); navigate?(section); openMainWindow?(); NSApp.activate()
        case .systemSettings(let url):
            guard NSWorkspace.shared.open(url) else { actionFailed = true; return }
            hide(restoreFocus: false)
        case .application(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { actionFailed = true; return }
            executing = true
            let token = presentationID
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
                Task { @MainActor in
                    guard let self, self.presentationID == token else { return }
                    self.executing = false
                    if error == nil { self.hide(restoreFocus: false) } else { self.actionFailed = true }
                }
            }
        }
    }
}

// Adapted from Tinycast PalettePanel, Copyright (C) 2026 Abue Ammar.
// AGPL-3.0-or-later; used under AGPL-3.0. Source: c5cff8cbb9b7e12ac75c058da9573045c76029b7.
// Modified 2026-09-23: minimal nonactivating panel, IME-safe navigation, no external event taps.
@MainActor final class LauncherPanel: NSPanel {
    var navigationEnabled: (() -> Bool)?
    var onTab: (() -> Void)?
    var onEscape: (() -> Void)?
    var onArrow: ((Int) -> Void)?
    var onSubmit: (() -> Void)?
    var onResign: (() -> Void)?
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        identifier = .init("launcher.panel"); title = "Mac Manager Launcher"
        isFloatingPanel = true; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        isReleasedWhenClosed = false; hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
    }
    func focusSearchField() {
        func find(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.identifier?.rawValue == "launcher.search" { return field }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        if let contentView, let field = find(in: contentView) { makeFirstResponder(field) }
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() { super.resignKey(); onResign?() }
    override func sendEvent(_ event: NSEvent) {
        let composing = (firstResponder as? NSTextView)?.hasMarkedText() == true
        if event.type == .keyDown, !composing, navigationEnabled?() != false,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            switch event.keyCode {
            case 48: onTab?(); return
            case 53: onEscape?(); return
            case 125: onArrow?(1); return
            case 126: onArrow?(-1); return
            case 36, 76: onSubmit?(); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}
