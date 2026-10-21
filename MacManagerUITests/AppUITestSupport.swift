import AppKit
import XCTest

class AppUITestSupport: XCTestCase {
    @MainActor
    var expectedClipboardIslandHeight: CGFloat {
        let screen = NSScreen.screens.first { candidate in
            guard let id = candidate.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        } ?? NSScreen.main!
        return max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY, 24) + 306
    }

    @MainActor
    func checkMusicSectionResize(reduceMotion: Bool) throws {
        let app = launch(reset: true, islandReduceMotion: reduceMotion)
        defer { app.terminate() }
        element("navigation.island", in: app).click()
        let debug = element("island.debug.music", in: app)
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Open Island"].click()
        XCTAssertTrue(app.buttons["island.section.music"].waitForExistence(timeout: 5))
        app.buttons["island.section.music"].click()
        let compact = NSPredicate { _, _ in abs(self.element("island.panel", in: app).frame.height - 250) < 1 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: compact, object: app)], timeout: 3), .completed)
        XCTAssertTrue(app.staticTexts["Test song 1"].waitForExistence(timeout: 5))
        app.buttons["music.play"].click()
        XCTAssertTrue(app.buttons["music.pause"].waitForExistence(timeout: 3))
        app.buttons["music.next"].click()
        XCTAssertTrue(app.staticTexts["Test song 2"].waitForExistence(timeout: 3))
        app.buttons["music.previous"].click()
        XCTAssertTrue(app.staticTexts["Test song 1"].waitForExistence(timeout: 3))
        app.buttons["island.section.clipboard"].click()
        for _ in 0..<3 {
            app.buttons["island.section.music"].click()
            app.buttons["island.section.clipboard"].click()
        }
        let expanded = NSPredicate { _, _ in abs(self.element("island.panel", in: app).frame.height - self.expectedClipboardIslandHeight) < 1 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expanded, object: app)], timeout: 3), .completed)
        let idle = NSPredicate(format: "label == %@ OR value == %@", "visible=0;work=0;artwork=0", "visible=0;work=0;artwork=0")
        app.buttons["island.close"].click()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: idle, object: debug)], timeout: 3), .completed)
    }

    @MainActor
    func checkIslandHiddenPresentation(reduceMotion: Bool) throws {
        let app = launch(reset: true, clipboardFixture: true, islandReduceMotion: reduceMotion)
        defer { app.terminate() }
        element("navigation.island", in: app).click()
        let state = element("island.debug.presentation", in: app)
        let idle = NSPredicate(format: "label == %@ OR value == %@",
            "hidden;host=0;work=0;active=0;transition=0;history=2",
            "hidden;host=0;work=0;active=0;transition=0;history=2")
        for _ in 0..<3 {
            app.menuBars.menuBarItems["View"].click()
            app.menuItems["Open Island"].click()
            let field = app.textFields["island.search"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.typeText("Project")
            let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "island.clipboard.restore.")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 3))
            field.typeKey(.return, modifierFlags: [])
            field.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(field.waitForNonExistence(timeout: 3))
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: idle, object: state)], timeout: 3), .completed)
        }
        // Closing invalidates search work immediately, even before results arrive.
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Open Island"].click()
        let field = app.textFields["island.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("no matching content")
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: idle, object: state)], timeout: 3), .completed)
    }

    @MainActor
    func performAccessibilityAudit(
        in app: XCUIApplication,
        for auditTypes: XCUIAccessibilityAuditType,
        within surface: XCUIElement? = nil
    ) throws {
        // XCTest audits the whole process, including dimmed windows behind sheets.
        // Keep checks on the visible surface being exercised, not its backdrop.
        let surfaceSnapshot = try surface?.snapshot()
        func contains(_ snapshot: any XCUIElementSnapshot, _ element: XCUIElement) -> Bool {
            if snapshot.elementType == element.elementType,
               snapshot.identifier == element.identifier,
               snapshot.label == element.label,
               !snapshot.identifier.isEmpty || snapshot.frame == element.frame {
                return true
            }
            return snapshot.children.contains { contains($0, element) }
        }
        try app.performAccessibilityAudit(for: auditTypes) { issue in
            guard let element = issue.element else {
                return false
            }
            if let surfaceSnapshot, element.exists, !contains(surfaceSnapshot, element) {
                return true
            }

            let isAnonymousDisabledGroup = element.elementType == .group
                && element.identifier.isEmpty
                && element.label.isEmpty
                && !element.isEnabled
            let isLayoutGroup = issue.auditType == .sufficientElementDescription
                && isAnonymousDisabledGroup
            let isSidebarNavigationLink = issue.auditType == .sufficientElementDescription
                && issue.compactDescription == "Unknown role"
                && element.elementType == .button
                && element.identifier.hasPrefix("navigation.")
            let isNativePickerAction = issue.auditType == .action
                && issue.compactDescription == "Action is missing"
                && element.elementType == .popUpButton
                && ["settings.language", "metrics.interval", "launcher.modifiers", "launcher.key"].contains(element.identifier)
            let isWindowControlContainer = issue.auditType == .parentChild
                && isAnonymousDisabledGroup
            let isSystemTouchBar = issue.auditType == .sufficientElementDescription
                && element.elementType == .touchBar
                && !element.isEnabled
            let sidebarLabels = [
                "Overview", "Sensors", "Network", "Scroll", "Dock", "Settings",
                "Przegląd", "Czujniki", "Sieć", "Przewijanie", "Ustawienia"
            ]
            let isNativeSidebarSelectionContrast = issue.auditType == .contrast
                && element.elementType == .staticText
                && sidebarLabels.contains(element.value as? String ?? element.label)

            // XCTest reports framework-owned SwiftUI, Liquid Glass and window chrome as findings.
            // Their actionable descendants and labels remain subject to every audit.
            let isFrameworkIssue = isLayoutGroup || isSidebarNavigationLink || isNativePickerAction
                || isWindowControlContainer || isSystemTouchBar
                || isNativeSidebarSelectionContrast
            if !isFrameworkIssue {
                // Keep enough context even if XCTest cannot attach a screenshot.
                print("AX audit: \(issue.compactDescription); type=\(element.elementType); id=\(element.identifier)")
                print(element.debugDescription)
            }
            return isFrameworkIssue
        }
    }

    @MainActor
    func launch(
        reset: Bool,
        liveMetrics: Bool = false,
        clipboardFixture: Bool = false,
        clipboardWriteFailure: Bool = false,
        islandClipboardFixture: Bool = false,
        islandDenseClipboardFixture: Bool = false,
        islandReduceMotion: Bool = false,
        islandConstrainedLayout: Bool = false,
        musicDenied: Bool = false,
        podcastAccessRequired: Bool = false,
        launcherLiveTesting: Bool = false,
        scrollPermission: Bool = false,
        inputMonitoringRequired: Bool = false,
        loginItemRequiresApproval: Bool = false,
        launchedAtLogin: Bool = false,
        updateFixture: UpdateFixture = .noRelease,
        expectsWindow: Bool = true
    ) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if reset { app.launchArguments.append("--reset-preferences") }
        if liveMetrics { app.launchArguments.append("--live-metrics") }
        if launcherLiveTesting { app.launchArguments.append("--launcher-live-testing") }
        if clipboardFixture { app.launchArguments.append("--clipboard-fixture") }
        if clipboardWriteFailure { app.launchArguments.append("--clipboard-write-failure") }
        if islandClipboardFixture { app.launchArguments.append("--island-clipboard-fixture") }
        if islandDenseClipboardFixture { app.launchArguments.append("--island-dense-clipboard-fixture") }
        if islandReduceMotion { app.launchArguments.append("--island-reduce-motion") }
        if islandConstrainedLayout { app.launchArguments.append("--island-constrained-layout") }
        if musicDenied { app.launchArguments.append("--music-denied") }
        if podcastAccessRequired { app.launchArguments.append("--podcast-access-required") }
        if scrollPermission { app.launchArguments.append("--scroll-permission-granted") }
        if inputMonitoringRequired { app.launchArguments.append("--scroll-input-monitoring-required") }
        if loginItemRequiresApproval { app.launchArguments.append("--login-item-requires-approval") }
        if launchedAtLogin { app.launchArguments.append("--launched-at-login") }
        if let argument = updateFixture.argument { app.launchArguments.append(argument) }
        app.launch()
        if expectsWindow {
            app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout: 2) {
                app.typeKey("1", modifierFlags: .command)
            }
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        }
        return app
    }

    enum UpdateFixture {
        case noRelease
        case current
        case available
        case failure
        case offline

        var argument: String? {
            switch self {
            case .noRelease: nil
            case .current: "--update-current"
            case .available: "--update-available"
            case .failure: "--update-failure"
            case .offline: "--update-offline"
            }
        }
    }

    @MainActor
    func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func switchValue(_ element: XCUIElement) -> Int? {
        if let number = element.value as? NSNumber { return number.intValue }
        if let text = element.value as? String { return Int(text) }
        return nil
    }

    @MainActor
    func revealIslandToggle(_ target: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["main.detailScroll"]
        for _ in 0..<15 {
            let frame = target.frame
            let viewport = scroll.frame
            if frame.minY > viewport.minY + 15 && frame.maxY < viewport.maxY - 15 { break }
            scroll.hover()
            scroll.scroll(byDeltaX: 0, deltaY: frame.minY < viewport.minY + 15 ? 220 : -220)
        }
        XCTAssertTrue(target.isHittable)
    }

    @MainActor
    func scrollTo(_ target: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews["main.detailScroll"]
        let window = app.windows.firstMatch
        var polarity = 1.0
        for _ in 0..<15 {
            let frame = target.frame, windowFrame = window.frame
            let viewport = scrollView.frame.intersection(windowFrame).insetBy(dx: 8, dy: 12)
            if target.isHittable && viewport.contains(frame) { return }
            let point = window.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: viewport.midX - windowFrame.minX, dy: viewport.midY - windowFrame.minY))
            let distance = abs(frame.midY - viewport.midY)
            point.hover()
            point.scroll(byDeltaX: 0, deltaY: (frame.midY > viewport.midY ? 300 : -300) * polarity)
            if abs(target.frame.midY - viewport.midY) >= distance - 1 { polarity *= -1 }
        }
    }

    @MainActor
    func waitForWindow(in app: XCUIApplication, exists: Bool) -> Bool {
        let predicate = NSPredicate(format: "exists == %@", NSNumber(value: exists))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.windows.firstMatch)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    func waitForElement(_ element: XCUIElement, exists: Bool) -> Bool {
        let predicate = NSPredicate(format: "exists == %@", NSNumber(value: exists))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
