import AppKit
import MacManagerCore
import Observation
import SwiftUI

@MainActor @Observable
final class LauncherController: ApplicationLifecycleParticipant {
    let model = LauncherSearchModel()
    private(set) var shortcutFailed = false
    private(set) var actionFailed = false
    private(set) var visible = false
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored var navigate: ((String) -> Void)?
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let hotKey = LauncherHotKey()
    @ObservationIgnored private var panel: LauncherPanel?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private let testing: Bool
    private var usesRealShortcut: Bool { !testing || ProcessInfo.processInfo.arguments.contains("--launcher-live-testing") }
    @ObservationIgnored private var running = false
    @ObservationIgnored private var presentationID = UUID()
    private(set) var executing = false
    var strings: AppStrings { AppStrings(languageCode: preferences.language.resolvedCode()) }

    init(preferences: PreferencesStore, testing: Bool = false) { self.preferences = preferences; self.testing = testing }
    func start() {
        guard !running else { return }; running = true
        hotKey.onPress = { [weak self] in self?.toggle() }
        if usesRealShortcut { shortcutFailed = !hotKey.register(preferences.launcherShortcut) }
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
        observers.forEach { $0.0.removeObserver($0.1) }; observers = []
    }
    @discardableResult func updateShortcut(_ value: LauncherShortcut) -> Bool {
        guard value.isValid else { return false }
        let success = !usesRealShortcut || hotKey.register(value)
        shortcutFailed = !success
        if success { preferences.launcherShortcut = value }
        return success
    }
    func toggle() { visible ? hide() : show() }
    func show() {
        guard running else { return }
        if visible { panel?.makeKeyAndOrderFront(nil); return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        actionFailed = false; executing = false; presentationID = UUID()
        let commands = AppSection.allCases.map { section in
            LauncherEntry(id: "command:" + section.rawValue, title: strings(section.titleKey),
                subtitle: "Mac Manager", symbol: section.symbol, action: .section(section.rawValue),
                alternateNames: [AppStrings(languageCode: "en")(section.titleKey), AppStrings(languageCode: "pl")(section.titleKey)])
        }
        model.load(providers: testing && !usesRealShortcut ? [] : [ApplicationProvider(), SystemSettingsProvider()],
                   language: preferences.language.resolvedCode(), commands: commands)
        let panel = self.panel ?? LauncherPanel()
        self.panel = panel
        panel.onEscape = { [weak self] in
            guard let self else { return }
            if self.model.query.isEmpty { self.hide() } else { self.model.search("") }
        }
        panel.onArrow = { [weak self] in self?.model.moveSelection($0) }
        panel.onSubmit = { [weak self] in self?.performSelected() }
        panel.onResign = { [weak self] in self?.hide(restoreFocus: false) }
        let hosting = NSHostingView(rootView: LauncherView(controller: self)
            .environment(\.locale, preferences.locale).preferredColorScheme(.dark).tint(AppTheme.accent))
        hosting.sizingOptions = []
        panel.contentView = hosting
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let width = min(680.0, frame.width - 40)
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.maxY - min(160, frame.height / 5) - 90,
                              width: width, height: 90), display: false)
        visible = true
        panel.makeKeyAndOrderFront(nil)
    }
    func resize(rowCount: Int) {
        guard visible, let panel else { return }
        let height: CGFloat = model.query.isEmpty ? 90 : 90 + CGFloat(min(max(rowCount, 1), 7)) * 56 + 32
        var frame = panel.frame
        let available = panel.screen?.visibleFrame ?? frame
        let bounded = min(height, available.height - 40)
        frame.origin.y += frame.height - bounded; frame.size.height = bounded
        frame.origin.y = max(frame.origin.y, available.minY + 20)
        panel.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    func hide(restoreFocus: Bool = true) {
        guard visible else { return }
        visible = false; presentationID = UUID(); executing = false
        panel?.orderOut(nil); panel?.contentView = nil
        model.cancel(); actionFailed = false
        if restoreFocus, let previousApplication, !previousApplication.isTerminated,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate()
        }
        previousApplication = nil
    }
    func performSelected() { if !model.query.isEmpty, let entry = model.selected { perform(entry) } }
    func perform(_ entry: LauncherEntry) {
        guard visible, !executing, model.results.contains(where: { $0.id == entry.id }) else { return }
        switch entry.action {
        case .section(let section):
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
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() { super.resignKey(); onResign?() }
    override func sendEvent(_ event: NSEvent) {
        let composing = (firstResponder as? NSTextView)?.hasMarkedText() == true
        if event.type == .keyDown, !composing,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            switch event.keyCode {
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
