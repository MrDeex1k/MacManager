// Focus recovery inspired by Tinycast 62abccdfc6cc06df7fc027099a4defe551386a88.
// Modified 2026-10-12: owned AppKit menus, presentation guards and selection/IME protection.
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
    var focusControlsRequest = 0
    var customizationEntry: LauncherEntry? {
        didSet {
            if oldValue != nil && customizationEntry == nil { restoreSearchFocus(after: presentationID) }
        }
    }
    @ObservationIgnored private var rowMenuOpen = false
    @ObservationIgnored private var searchSelection: (query: String, range: NSRange)?
    var focusPresentationID: UUID { presentationID }
    var options: LauncherPreferences { preferences.launcher }
    var showsResults: Bool { clipboardMode || !model.query.isEmpty }
    @ObservationIgnored private let clipboardSearch = ClipboardSearchModel()
    @ObservationIgnored private let calculator = LocalCalculatorWorker()
    @ObservationIgnored private let files = LauncherFileSearch()
    @ObservationIgnored private let applicationIcons = LauncherIconCache()
    var catalogRefreshSeconds: Double = 60 { didSet { model.catalogRefreshSeconds = catalogRefreshSeconds } }
    @ObservationIgnored private var shortcutCleanup: Task<Void, Never>?

    @ObservationIgnored private let itemHotKeys = LauncherItemShortcuts()
    private(set) var itemShortcutFailures: Set<String> = []
    private(set) var shortcutFailed = false
    private(set) var actionFailed = false
    private(set) var visible = false
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored var navigate: ((String) -> Void)?
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let actionExecutor: LauncherActionExecutor
    @ObservationIgnored private let hotKey = LauncherHotKey()
    @ObservationIgnored private var panel: LauncherPanel?
    @ObservationIgnored private var hosting: NSHostingView<AnyView>?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private let observers = NotificationTokens()
    @ObservationIgnored private let testing: Bool
    private var usesRealShortcut: Bool { !testing || UITestConfiguration.current.contains("--launcher-live-testing") }
    @ObservationIgnored private var running = false
    @ObservationIgnored private var presentationID = UUID()
    private(set) var executing = false
    var strings: AppStrings { AppStrings(languageCode: preferences.language.resolvedCode()) }

    init(preferences: PreferencesStore, testing: Bool = false) {
        self.preferences = preferences; self.testing = testing
        actionExecutor = LauncherActionExecutor(testing: testing)
    }
    func start() {
        guard !running else { return }; running = true
        model.onCatalogLoaded = { [weak self] entries in self?.reconcileCatalogApplications(entries) }
        hotKey.onPress = { [weak self] in self?.toggle() }
        if usesRealShortcut { shortcutFailed = !hotKey.register(preferences.launcherShortcut) }
        model.additionalResults = { [weak self] query in
            guard let self, self.visible else { return [] }
            if self.clipboardMode {
                guard let clipboard = self.clipboard, !clipboard.suspended else { return [] }
                let entries = try await self.clipboardSearch.search(.init(query: query, service: clipboard), service: clipboard, limit: 40)
                try Task.checkCancellation()
                guard self.visible, self.clipboardMode, !clipboard.suspended else { return [] }
                return entries.map {
                        LauncherEntry(id: "clipboard:" + $0.id.uuidString,
                            title: $0.text.map { String($0.prefix(200)) } ?? self.strings("clipboard.image"),
                            subtitle: self.strings("clipboard.restore"), symbol: $0.record.kind == .text ? "doc.plaintext" : "photo",
                            action: .clipboard($0.id))
                    }
            }
            let context = LocalCalculator.Context(language: self.preferences.language.resolvedCode())
            var results = try await self.calculator.result(query, context: context).map { [$0] } ?? []
            try Task.checkCancellation()
            let options = self.preferences.launcher, filter = self.fileFilter
            if results.isEmpty && options.filesEnabled && query.count >= 2 {
                try await Task.sleep(for: .milliseconds(120))
                results += try await self.files.search(query, roots: options.folders, filter: filter)
            }
            return results
        }
        registerItemShortcuts()
        reconcileApplicationShortcuts()
        SystemSessionMonitor.shared.subscribe(in: observers) { [weak self] state in
            guard state.suspended, let self else { return }
            self.hide(restoreFocus: false); self.model.cancel()
            self.shortcutCleanup?.cancel(); self.shortcutCleanup = nil
        }
    }
    func stop() {
        running = false; hide(restoreFocus: false); hotKey.stop()
        presentationID = UUID(); executing = false
        model.cancel(); shortcutCleanup?.cancel(); shortcutCleanup = nil
        applicationIcons.clear()
        panel?.rowMenus.stop()
        panel?.contentView = nil; hosting = nil
        itemHotKeys.stop()
        observers.removeAll()
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
        applicationIcons.refreshIfNeeded(after: catalogRefreshSeconds)
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
        panel.navigationEnabled = { [weak self] in self?.customizationEntry == nil && self?.rowMenuOpen == false }
        panel.onTab = { [weak self] in self?.toggleMode() }
        panel.onFocusControls = { [weak self] in self?.focusControlsRequest += 1 }
        panel.onArrow = { [weak self] in self?.model.moveSelection($0) }
        panel.onSubmit = { [weak self] in self?.performSelected() }
        panel.onResign = { [weak self] in if self?.customizationEntry == nil && self?.rowMenuOpen == false { self?.hide(restoreFocus: false) } }
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
        restoreSearchFocus(after: presentationID)
    }
    func beginRowMenu() -> UUID {
        rowMenuOpen = true
        searchSelection = panel?.searchSelection().map { (model.query, $0) }
        return presentationID
    }
    func endRowMenu(_ token: UUID) {
        guard token == presentationID else { return }
        rowMenuOpen = false
        if customizationEntry == nil, panel?.isKeyWindow != true {
            hide(restoreFocus: false)
            return
        }
        restoreSearchFocus(after: token)
    }
    func openCustomization(_ entry: LauncherEntry) {
        if !rowMenuOpen { searchSelection = panel?.searchSelection().map { (model.query, $0) } }
        customizationEntry = entry
    }
    func restoreSearchFocus(after token: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.visible, self.presentationID == token,
                  !self.rowMenuOpen, self.customizationEntry == nil,
                  let panel = self.panel, panel.isVisible, panel.isKeyWindow else { return }
            let selection = self.searchSelection
            panel.focusSearchField(selection: selection?.query == self.model.query ? selection?.range : nil)
            self.searchSelection = nil
        }
    }

    func toggleMode(clipboard: Bool? = nil) {
        clipboardSearch.reset()
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
            guard itemHotKeys.register(id: id, shortcut: shortcut, enabled: usesRealShortcut, action: { [weak self] in
                guard let self, let current = self.preferences.launcher.items[id] else { return }
                self.execute(current.entry)
            }) else { itemShortcutFailures.insert(id); return false }
        } else { itemHotKeys.remove(id) }
        itemShortcutFailures.remove(id)
        return true
    }
    func removeCustomization(_ id: String) {
        itemHotKeys.remove(id)
        preferences.launcher.items.removeValue(forKey: id)
        itemShortcutFailures.remove(id)
        refreshResults()
    }
    private func registerItemShortcuts() {
        for value in preferences.launcher.items.values { _ = registerCustomization(value) }
    }

    func applicationIcon(at url: URL) -> NSImage { applicationIcons.image(at: url) }

    private func reconcileCatalogApplications(_ entries: [LauncherEntry]) {
        var updated = preferences.launcher
        for entry in entries {
            guard case .application = entry.action, var item = updated.items[entry.id], item.entry != entry else { continue }
            if case .application(let oldURL) = item.entry.action {
                applicationIcons.remove(oldURL)
            }
            item.entry = entry
            updated.items[entry.id] = item
        }
        if updated != preferences.launcher {
            preferences.launcher = updated
            model.preferences = updated
        }
    }

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
                self.itemHotKeys.remove(item.entry.id)
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
        clipboardSearch.reset()
        guard visible else { return }
        visible = false; presentationID = UUID(); executing = false
        rowMenuOpen = false; searchSelection = nil
        panel?.orderOut(nil)
        // Reuse the host, but release the private mode's SwiftUI subtree immediately.
        if clipboardMode { hosting?.rootView = AnyView(Color.clear) }
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
        guard running, !executing else { return }
        executing = true
        let token = presentationID
        Task {
            let outcome = await actionExecutor.execute(entry, options: preferences.launcher, clipboard: clipboard)
            guard running, token == presentationID else { return }
            executing = false
            switch outcome {
            case .copied: hide()
            case .opened: hide(restoreFocus: false)
            case .failed: actionFailed = true
            case .section(let section):
                if section == "clipboard" {
                    if !visible { show() }
                    toggleMode(clipboard: true)
                } else {
                    hide(restoreFocus: false); navigate?(section); openMainWindow?(); NSApp.activate()
                }
            }
        }
    }
}
