import AppKit
import MacManagerCore
import Observation
import QuartzCore
import SwiftUI

extension IslandSection {
    var titleKey: String {
        switch self {
        case .clipboard: "island.clipboard.tab"
        case .music: "music.title"
        case .podcast: "podcast.title"
        case .spotify: "spotify.title"
        }
    }
}

@MainActor @Observable
final class IslandCoordinator: ApplicationLifecycleParticipant {
    let preferences: PreferencesStore
    private(set) var visible = false
    private(set) var closing = false
    private(set) var transitioning = false
    private(set) var shortcutFailed = false
    private(set) var clipboardModel: IslandClipboardModel?
    private var players: [MediaSource: MusicService] = [:]
    var music: MusicService? { players[.music] }
    var podcasts: MusicService? { players[.podcast] }
    private var activePlayer: MusicService? { MediaSource.allCases.first { $0.section == section }.flatMap { players[$0] } }
    private(set) var section: IslandSection = .clipboard
    private(set) var displayedSection: IslandSection = .clipboard
    private(set) var sectionOpacity = 1.0
    @ObservationIgnored private var sectionTask: Task<Void, Never>?
    @ObservationIgnored private var sectionGeneration = 0
    #if DEBUG
    @ObservationIgnored private var sectionPreparedAt: CFTimeInterval = 0
    @ObservationIgnored private var sectionRevealDelay: Double = 0
    #endif
    func connectPlayer(_ service: MusicService, source: MediaSource) { players[source] = service }
    var availableSections: [IslandSection] {
        IslandSection.allCases.filter { preferences.island.sections.contains($0) }
    }
    func selectSection(_ value: IslandSection) {
        guard preferences.island.enabled, preferences.island.sections.contains(value), value != section else { return }
        section = value
        cancelSectionChange()
        guard visible else { displayedSection = value; return }
        if reduceMotion { renderSelectedSection(); return }
        let token = sectionGeneration
        withAnimation(.easeOut(duration: 0.075)) { sectionOpacity = 0 }
        sectionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(75)) } catch { return }
            guard let self, self.visible, token == self.sectionGeneration else { return }
            self.renderSelectedSection()
            self.sectionTask = nil
        }
    }
    private func cancelSectionChange() {
        sectionGeneration += 1; sectionTask?.cancel(); sectionTask = nil
    }
    private func renderSelectedSection() {
        clipboardModel?.reset(); players.values.forEach { $0.setVisible(false) }
        panel?.makeFirstResponder(nil)
        // Prepare in-memory entries/selection before mounting the clipboard subtree.
        if section == .clipboard { clipboardModel?.activate() }
        else { activePlayer?.setVisible(true) }
        #if DEBUG
        sectionPreparedAt = CACurrentMediaTime()
        #endif
        displayedSection = section
        resizeForSection()
    }
    private func revealSectionContent() {
        guard section == displayedSection, sectionOpacity < 1 else { return }
        #if DEBUG
        sectionRevealDelay = (CACurrentMediaTime() - sectionPreparedAt) * 1000
        #endif
        if reduceMotion { sectionOpacity = 1 }
        else { withAnimation(.easeOut(duration: 0.14)) { sectionOpacity = 1 } }
    }
    private func settleSectionChange() {
        cancelSectionChange(); sectionOpacity = 1
        if visible { renderSelectedSection() }
    }
    var debugMusicState: String {
        "visible=\(music?.visible == true ? 1 : 0);work=\(music?.hasPendingWork == true ? 1 : 0);artwork=\(music?.snapshot.artwork == nil ? 0 : 1)"
    }
    var debugPodcastsState: String {
        "visible=\(podcasts?.visible == true ? 1 : 0);work=\(podcasts?.hasPendingWork == true ? 1 : 0);artwork=\(podcasts?.snapshot.artwork == nil ? 0 : 1)"
    }
    #if DEBUG
    func setSessionSuspendedForTesting(_ value: Bool) {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        if value { suspend("test-session") } else { resume("test-session") }
    }
    #endif
    var query: String {
        get { clipboardModel?.query ?? "" }
        set { clipboardModel?.query = newValue }
    }
    private(set) var topInset: CGFloat = 24
    var strings: AppStrings { AppStrings(languageCode: preferences.language.resolvedCode()) }
    @ObservationIgnored private var running = false
    @ObservationIgnored private var suspensionReasons: Set<String> = []
    private var suspended: Bool { !suspensionReasons.isEmpty }
    @ObservationIgnored private var menuTracking = false
    @ObservationIgnored private var interaction = IslandInteraction()
    @ObservationIgnored private var panel: IslandPanel?
    @ObservationIgnored private var transitionHost: IslandTransitionHost?
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var transitionGeneration = 0
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ||
            (ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--island-reduce-motion"))
    }
    var debugPresentationState: String {
        "\(visible ? "visible" : closing ? "closing" : "hidden");host=\(transitionHost == nil ? 0 : 1);work=\(clipboardModel?.hasPendingWork == true ? 1 : 0);active=\(clipboardModel?.active == true ? 1 : 0);transition=\(transitioning || sectionTask != nil ? 1 : 0);history=\(clipboardModel?.service.entries.count ?? 0)"
    }
    #if DEBUG
    var debugAnimationState: String {
        "driver=\(transitionHost?.isResizing == true ? 1 : 0);\(transitionHost?.resizeTimingSummary ?? "idle");revealMs=\(String(format: "%.2f", sectionRevealDelay))"
    }
    #endif
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private var previousWindow: NSWindow?
    @ObservationIgnored private var wakeup: DispatchWorkItem?
    @ObservationIgnored private var scheduledDeadline: TimeInterval?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private let observers = NotificationTokens()
    @ObservationIgnored private let hotKey = LauncherHotKey()
    @ObservationIgnored private var activationFrame = NSRect.zero
    @ObservationIgnored private var panelFrame = NSRect.zero
    @ObservationIgnored private var screen: NSScreen?
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(preferences: PreferencesStore) { self.preferences = preferences }
    func connectClipboard(_ service: ClipboardService) { clipboardModel = IslandClipboardModel(service: service) }

    func start() {
        guard !running else { return }
        running = true
        hotKey.onPress = { [weak self] in self?.toggleFromKeyboard() }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointer(event) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointer(event) }
            return event
        }) { monitors.append(monitor) }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.reposition() }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.environmentChanged() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.environmentChanged() }
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) {
            if $0.closing { $0.finishClosing() }
            else if $0.visible { $0.settleSectionChange() }
        }
        observe(.default, NSMenu.didBeginTrackingNotification) { $0.setMenuTracking(true) }
        observe(.default, NSMenu.didEndTrackingNotification) { $0.setMenuTracking(false) }
        SystemSessionMonitor.shared.subscribe(in: observers) { [weak self] state in
            guard let self else { return }
            if state.suspended { self.suspend("system-session") }
            else if self.suspensionReasons.contains("system-session") { self.resume("system-session") }
        }
        watchPreferences()
        reposition()
    }

    func stop() {
        running = false
        dismiss(restoreFocus: false, animated: false)
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        observers.removeAll()
        hotKey.stop(); interaction.reset()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (IslandCoordinator) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.running { action(self) } }
        }
        observers.append((center, token))
    }

    private func watchPreferences() {
        withObservationTracking {
            _ = preferences.island
            _ = preferences.language
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.watchPreferences()
            }
        }
        applyPreferences()
    }

    private func applyPreferences() {
        if preferences.island.enabled {
            if !preferences.island.sections.contains(section), let first = availableSections.first {
                cancelSectionChange()
                section = first
                sectionOpacity = 1
                if visible { renderSelectedSection() }
                else { displayedSection = first }
            }
            shortcutFailed = !hotKey.register(preferences.island.shortcut)
        } else { hotKey.stop(); shortcutFailed = false; dismiss(restoreFocus: true, animated: false) }
        if let panel { panel.title = strings("island.title") }
        environmentChanged()
    }

    func updateShortcut(_ value: LauncherShortcut) {
        guard value.isValid else { return }
        let registered = !preferences.island.enabled || hotKey.register(value)
        shortcutFailed = !registered
        if registered { preferences.island.shortcut = value }
    }

    private func suspend(_ reason: String) {
        suspensionReasons.insert(reason); dismiss(restoreFocus: false, animated: false); interaction.reset()
    }
    private func resume(_ reason: String) { suspensionReasons.remove(reason); reposition() }
    private func environmentChanged() {
        guard available else { dismiss(restoreFocus: false, animated: false); return }
        if visible, let panel, panel.isKeyWindow == false,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != previousApplication?.processIdentifier {
            dismiss(restoreFocus: false)
        }
    }

    private var available: Bool {
        running && !suspended && preferences.island.enabled && screen != nil &&
            (preferences.island.showsInFullScreen || !IslandWindowGeometry.isFullScreen(on: screen))
    }

    private func reposition() {
        dismiss(restoreFocus: false, animated: false); interaction.reset()
        screen = NSScreen.screens.first { candidate in
            guard let id = candidate.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        } ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.frame
        let geometry = IslandWindowGeometry.activation(on: screen)
        topInset = geometry.inset
        activationFrame = geometry.frame
        let width = geometry.panelWidth
        let height = sectionHeight(width: width)
        panelFrame = NSRect(x: frame.midX - width / 2, y: frame.maxY - height,
                            width: width, height: height)
        panel?.setFrame(panelFrame, display: true)
    }

    private func sectionHeight(width: CGFloat) -> CGFloat {
        sectionHeight(section, width: width)
    }
    var displayedSectionHeight: CGFloat { sectionHeight(displayedSection, width: panelFrame.width) }
    private func sectionHeight(_ section: IslandSection, width: CGFloat) -> CGFloat {
        if section != .clipboard { return 250 }
        #if DEBUG
        // Reproduce the constrained layout encountered while expanding from Music.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--island-constrained-layout") { return 250 }
        #endif
        // The shelf has a fixed card/indicator height; reserve only its actual
        // controls and spacing below the camera strip, rather than a target ratio.
        return topInset + 304
    }

    private func resizeForSection() {
        guard let screen, let panel, let transitionHost else { return }
        cancelTransition()
        let start = panel.frame
        let height = sectionHeight(width: panelFrame.width)
        panelFrame.origin.y = screen.frame.maxY - height
        panelFrame.size.height = height
        let target = panelFrame
        panel.minSize = .zero
        panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // Keep one observed SwiftUI tree (and one Glass surface) across section changes.
        transitionHost.stopAnimations()
        // Glass supplies its own rim/shadow. A WindowServer shadow adds a second,
        // stale silhouette when the transparent panel changes height.
        panel.hasShadow = false
        if reduceMotion || abs(start.height - target.height) < 0.5 {
            applySectionFrame(target)
            panel.minSize = target.size; panel.maxSize = target.size
            revealSectionContent()
            return
        }
        transitioning = true
        let token = transitionGeneration
        let scale = screen.backingScaleFactor
        transitionHost.animateResize(duration: 0.28, maximumFPS: screen.maximumFramesPerSecond) { [weak self] progress in
            guard let self, self.visible, token == self.transitionGeneration else { return }
            // The new subtree had a run-loop turn to mount. Reveal it on the
            // first display-paced frame, rather than waiting another 160 ms.
            self.revealSectionContent()
            let eased = progress * progress * progress * (progress * (progress * 6 - 15) + 10)
            let height = ((start.height + (target.height - start.height) * eased) * scale).rounded() / scale
            // Both bounds share their top edge; only the bottom edge moves.
            self.applySectionFrame(NSRect(x: target.minX, y: target.maxY - height,
                                           width: target.width, height: height))
        } completion: { [weak self] in
            guard let self, self.visible, token == self.transitionGeneration else { return }
            panel.minSize = target.size; panel.maxSize = target.size
            self.transitioning = false
        }
    }

    private func applySectionFrame(_ frame: NSRect) {
        guard panel?.frame != frame else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        panel?.setFrame(frame, display: false)
        transitionHost?.resizeGeometry(size: frame.size, topInset: topInset, collapsedWidth: activationFrame.width)
        CATransaction.commit()
    }

    private func handlePointer(_ event: NSEvent) {
        guard running, !suspended, preferences.island.enabled, screen != nil else { return }
        let point = NSEvent.mouseLocation
        let inside = activationFrame.contains(point) || (visible && (panel?.frame ?? panelFrame).contains(point))
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if visible && !inside { dismiss(restoreFocus: false) }
            return
        }
        // Fullscreen metadata is checked at the opening deadline, not for every mouse move.
        interaction.pointer(inside: inside, now: now)
        schedule()
    }

    private func schedule() {
        guard scheduledDeadline != interaction.deadline else { return }
        wakeup?.cancel(); wakeup = nil; generation += 1
        scheduledDeadline = interaction.deadline
        guard let deadline = interaction.deadline else { return }
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running, self.generation == token else { return }
            self.wakeup = nil; self.scheduledDeadline = nil
            self.interaction.advance(now: self.now)
            if self.interaction.expanded {
                if self.available { self.present(keyboard: false) }
                else { self.interaction.dismiss() }
            } else { self.dismiss(restoreFocus: false) }
        }
        wakeup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now), execute: work)
    }

    func showFromKeyboard() {
        guard available else { return }
        interaction.openForKeyboard(); schedule(); present(keyboard: true)
    }
    private func toggleFromKeyboard() { visible ? dismiss(restoreFocus: true) : showFromKeyboard() }

    private func present(keyboard: Bool) {
        if !visible {
            previousApplication = NSWorkspace.shared.frontmostApplication
            previousWindow = NSApp.keyWindow
            finishClosing()
            cancelSectionChange(); displayedSection = section; sectionOpacity = 1
            if section == .clipboard { clipboardModel?.activate() }
            else { activePlayer?.setVisible(true) }
            if let screen {
                let height = sectionHeight(width: panelFrame.width)
                panelFrame.origin.y = screen.frame.maxY - height
                panelFrame.size.height = height
            }
            let panel = panel ?? IslandPanel()
            self.panel = panel
            panel.title = strings("island.title")
            panel.onSectionSelect = { [weak self] index in
                guard IslandSection.allCases.indices.contains(index) else { return }
                self?.selectSection(IslandSection.allCases[index])
            }
            panel.onEscape = { [weak self] in self?.dismiss(restoreFocus: true) }
            panel.onMove = { [weak self] delta in if self?.section == .clipboard { self?.clipboardModel?.move(delta) } }
            panel.onSubmit = { [weak self] in
                if self?.section == .clipboard { self?.clipboardModel?.restoreSelected() }
                else { self?.activePlayer?.perform(.playPause) }
            }
            panel.onSpace = { [weak self] in
                guard let self, let player = self.activePlayer else { return false }
                player.perform(.playPause); return true
            }
            panel.onKeyChange = { [weak self] held in
                guard let self, self.visible else { return }
                self.interaction.hold(held || self.menuTracking, now: self.now); self.schedule()
            }
            // The panel owns its geometry. A hosting view with an unbounded SwiftUI height
            // must not publish min/max sizes that resize a non-key panel after orderFront.
            let root = AnyView(IslandView(coordinator: self)
                .environment(\.locale, preferences.locale)
                .preferredColorScheme(.dark))
            let host = IslandTransitionHost(root: root, size: panelFrame.size,
                                            topInset: topInset, collapsedWidth: activationFrame.width)
            transitionHost = host
            panel.contentView = host
            panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            panel.minSize = panelFrame.size
            panel.maxSize = panelFrame.size
            panel.setFrame(panelFrame, display: true)
            visible = true
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            beginTransition(opening: true)
        }
        if keyboard { panel?.makeKeyAndOrderFront(nil); if section == .clipboard { panel?.focusSearch() } }
    }

    private func setMenuTracking(_ value: Bool) {
        // Only hold an interaction in our key panel; unrelated app menus must not pin the island.
        guard visible, menuTracking || panel?.isKeyWindow == true else { return }
        menuTracking = value
        interaction.hold(value || panel?.isKeyWindow == true, now: now); schedule()
        if !value {
            let token = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.visible, self.generation == token,
                      !self.menuTracking else { return }
                self.panel?.makeKeyAndOrderFront(nil)
                if self.section == .clipboard { self.panel?.focusSearch() }
            }
        }
    }

    private func cancelTransition() {
        transitionHost?.stopResizeAnimation()
        transitionGeneration += 1; transitionTask?.cancel(); transitionTask = nil; transitioning = false
    }

    private func beginTransition(opening: Bool) {
        cancelTransition()
        guard let transitionHost else { return }
        transitioning = true
        panel?.hasShadow = false
        let token = transitionGeneration
        let duration = transitionHost.animate(opening: opening, reduceMotion: reduceMotion)
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, token == self.transitionGeneration else { return }
            if opening {
                self.transitionHost?.stopAnimations(); self.transitioning = false; self.transitionTask = nil
            } else { self.finishClosing() }
        }
    }

    private func finishClosing() {
        cancelTransition(); panel?.orderOut(nil); transitionHost?.stopAnimations()
        panel?.contentView = nil; transitionHost = nil; closing = false
    }

    func dismiss(restoreFocus: Bool, animated: Bool = true) {
        wakeup?.cancel(); wakeup = nil; generation += 1
        scheduledDeadline = nil
        interaction.dismiss()
        guard visible else { if !animated { finishClosing() }; return }
        let hadFocus = panel?.isKeyWindow == true
        visible = false; menuTracking = false
        cancelSectionChange(); sectionOpacity = 1; displayedSection = section
        clipboardModel?.reset()
        players.values.forEach { $0.setVisible(false) }
        panel?.makeFirstResponder(nil)
        panel?.ignoresMouseEvents = true
        if animated, let transitionHost {
            closing = true; transitionHost.clearPrivateContent(); beginTransition(opening: false)
        } else { finishClosing() }
        if restoreFocus && hadFocus {
            if let previousApplication, previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               !previousApplication.isTerminated { previousApplication.activate() }
            else { previousWindow?.makeKeyAndOrderFront(nil) }
        }
        previousApplication = nil; previousWindow = nil
    }
}

