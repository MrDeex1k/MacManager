import AppKit
import XCTest

final class AppShellTests: XCTestCase {
    @MainActor
    private var expectedClipboardIslandHeight: CGFloat {
        let screen = NSScreen.screens.first { candidate in
            guard let id = candidate.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        } ?? NSScreen.main!
        return max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY, 24) + 304
    }

    @MainActor
    func testIslandGlassSectionResizeAndClose() throws {
        let app = launch(reset: true, clipboardFixture: true, islandClipboardFixture: true, islandDenseClipboardFixture: true)
        defer { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
        XCTAssertFalse(app.popUpButtons["island.background"].exists)
        let timing = element("island.debug.animation", in: app)
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Open Island"].click()
        XCTAssertTrue(app.textFields["island.search"].waitForExistence(timeout: 5))
        let proof = XCTAttachment(screenshot: element("island.panel", in: app).screenshot())
        proof.name = "Island native Liquid Glass background"
        proof.lifetime = .keepAlways
        add(proof)
        let panel = element("island.panel", in: app)
        let top = panel.frame.minY
        for cycle in 1...3 {
            app.buttons["island.section.music"].click()
            XCTAssertTrue(app.staticTexts["Test song 1"].waitForExistence(timeout: 5))
            let compact = NSPredicate { _, _ in abs(panel.frame.height - 250) < 0.5 }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: compact, object: app)], timeout: 3), .completed)
            XCTAssertEqual(panel.frame.minY, top, accuracy: 0.5)
            let stopped = NSPredicate { _, _ in
                let value = (timing.value as? String) ?? timing.label
                return value.hasPrefix("driver=0;callbacks=")
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stopped, object: app)], timeout: 3), .completed)
            let timingProof = XCTAttachment(string: (timing.value as? String) ?? timing.label)
            timingProof.name = "Display-paced music resize \(cycle)"
            timingProof.lifetime = .keepAlways
            add(timingProof)
            let musicProof = XCTAttachment(screenshot: panel.screenshot())
            musicProof.name = "Glass music after resize \(cycle)"
            musicProof.lifetime = .keepAlways
            add(musicProof)
            app.buttons["island.section.clipboard"].click()
            XCTAssertTrue(app.textFields["island.search"].waitForExistence(timeout: 5))
            let expanded = NSPredicate { _, _ in abs(panel.frame.height - self.expectedClipboardIslandHeight) < 0.5 }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expanded, object: app)], timeout: 3), .completed)
            XCTAssertEqual(panel.frame.minY, top, accuracy: 0.5)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stopped, object: app)], timeout: 3), .completed)
            let returnTiming = XCTAttachment(string: (timing.value as? String) ?? timing.label)
            returnTiming.name = "Display-paced clipboard return \(cycle)"
            returnTiming.lifetime = .keepAlways
            add(returnTiming)
            let firstCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "island.clipboard.restore.")).firstMatch
            XCTAssertTrue(firstCard.isHittable)
            XCTAssertGreaterThanOrEqual(firstCard.frame.minY, panel.frame.minY)
            XCTAssertLessThanOrEqual(firstCard.frame.maxY, panel.frame.maxY)
        }
        let resizedProof = XCTAttachment(screenshot: panel.screenshot())
        resizedProof.name = "Glass clipboard after repeated resize"
        resizedProof.lifetime = .keepAlways
        add(resizedProof)
        app.buttons["island.close"].click()
        XCTAssertTrue(element("island.panel", in: app).waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testAppleMusicControlsAndHiddenWork() throws {
        try checkMusicSectionResize(reduceMotion: false)
    }

    @MainActor
    func testIslandConstrainedClipboardKeepsHeaderAnchored() throws {
        let app = launch(reset: true, clipboardFixture: true, islandConstrainedLayout: true)
        defer { app.terminate() }
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Open Island"].click()
        let clipboard = app.buttons["island.section.clipboard"]
        let music = app.buttons["island.section.music"]
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertTrue(music.isHittable, "Oversized clipboard content must not push the header outside the window")
        let top = clipboard.frame.minY
        XCTAssertGreaterThanOrEqual(top, element("island.panel", in: app).frame.minY + 40)
        let closeTop = app.buttons["island.close"].frame.minY
        music.click()
        XCTAssertTrue(app.staticTexts["Test song 1"].waitForExistence(timeout: 5))
        XCTAssertEqual(music.frame.minY, top, accuracy: 0.5)
        XCTAssertEqual(app.buttons["island.close"].frame.minY, closeTop, accuracy: 0.5)
        clipboard.click()
        XCTAssertTrue(app.textFields["island.search"].waitForExistence(timeout: 5))
        XCTAssertEqual(clipboard.frame.minY, top, accuracy: 0.5)
        XCTAssertEqual(app.buttons["island.close"].frame.minY, closeTop, accuracy: 0.5)
        let proof = XCTAttachment(screenshot: element("island.panel", in: app).screenshot())
        proof.name = "Constrained clipboard header stays anchored"
        proof.lifetime = .keepAlways
        add(proof)
    }

    @MainActor
    func testIslandSectionResizeReduceMotion() throws {
        try checkMusicSectionResize(reduceMotion: true)
    }

    @MainActor
    private func checkMusicSectionResize(reduceMotion: Bool) throws {
        let app = launch(reset: true, islandReduceMotion: reduceMotion)
        defer { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
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
    func testAppleMusicDeniedPermissionHasRecoveryAction() throws {
        let app = launch(reset: true, musicDenied: true)
        defer { app.terminate() }
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Open Island"].click()
        XCTAssertTrue(app.buttons["island.section.music"].waitForExistence(timeout: 5))
        app.buttons["island.section.music"].click()
        XCTAssertTrue(app.buttons["music.permissions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["music.play"].isEnabled)
        app.buttons["island.section.clipboard"].click()
        XCTAssertTrue(app.textFields["island.search"].waitForExistence(timeout: 3))
    }
    @MainActor
    func testIslandHiddenPresentationStopsAndReopens() throws {
        try checkIslandHiddenPresentation(reduceMotion: false)
    }
    @MainActor
    func testIslandReduceMotionStopsHiddenPresentation() throws {
        try checkIslandHiddenPresentation(reduceMotion: true)
    }
    @MainActor
    private func checkIslandHiddenPresentation(reduceMotion: Bool) throws {
        let app = launch(reset: true, clipboardFixture: true, islandReduceMotion: reduceMotion)
        defer { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
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
        field.typeText("no matching private content")
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: idle, object: state)], timeout: 3), .completed)
    }

    @MainActor
    func testIslandHoverAcrossActivationAndPanel() throws {
        let app = launch(reset: true)
        let primary = try XCTUnwrap(NSScreen.screens.first)
        let screen = NSScreen.screens.first { candidate in
            guard let id = candidate.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        } ?? primary
        let window = app.windows["main"]
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let inset = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let x = screen.frame.midX
        let top = primary.frame.maxY - screen.frame.maxY
        let activation = origin.withOffset(CGVector(dx: x - window.frame.minX,
                                                   dy: top + inset + 5 - window.frame.minY))
        let outside = origin.withOffset(CGVector(dx: x - window.frame.minX,
                                                   dy: top + inset + 400 - window.frame.minY))
        outside.hover()
        activation.hover()
        let field = app.textFields["island.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let panel = element("island.panel", in: app)
        XCTAssertEqual(panel.frame.minY, top, accuracy: 1, "Island must reach the physical screen edge, including the menu strip")
        XCTAssertEqual(panel.frame.height, inset + 304, accuracy: 1, "Hover must not expand the panel to screen height")
        XCTAssertEqual(panel.frame.width, min(560, screen.frame.width - 32), accuracy: 1)
        let layers = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let islandInfo = layers.first {
            guard ($0[kCGWindowLayer as String] as? Int) == NSWindow.Level.statusBar.rawValue + 1,
                  let bounds = $0[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return abs(rect.minX - panel.frame.minX) < 2 && abs(rect.minY - panel.frame.minY) < 2 &&
                abs(rect.width - panel.frame.width) < 2 && abs(rect.height - panel.frame.height) < 2
        }
        XCTAssertNotNil(islandInfo, "Island must draw above the menu bar")
        // Cross from the narrow activation strip into the wider panel without a click.
        field.hover()
        XCTAssertTrue(field.exists)
        XCTAssertEqual(panel.frame.height, inset + 304, accuracy: 1)
        outside.hover()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        activation.hover()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(panel.frame.height, inset + 304, accuracy: 1, "Reopening must retain the bounded height")
        outside.hover()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        app.terminate()
    }

    @MainActor
    func testIslandSharedClipboardSearchRestoreAndDelete() throws {
        let app = launch(reset: true, clipboardFixture: true, islandClipboardFixture: true)
        defer { app.terminate() }
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Open Island"].click()
        let field = app.textFields["island.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "island.clipboard.restore."))
        XCTAssertTrue(cards.element(boundBy: 2).waitForExistence(timeout: 5))
        XCTAssertGreaterThan(cards.element(boundBy: 1).frame.minX, cards.element(boundBy: 0).frame.minX)
        XCTAssertEqual(cards.element(boundBy: 1).frame.minY, cards.element(boundBy: 0).frame.minY, accuracy: 1)
        let viewport = element("island.panel", in: app).scrollViews.firstMatch
        XCTAssertTrue(viewport.exists)
        XCTAssertGreaterThanOrEqual(cards.element(boundBy: 0).frame.minY, viewport.frame.minY + 2)
        XCTAssertLessThanOrEqual(cards.element(boundBy: 0).frame.maxY, viewport.frame.maxY - 2)
        let firstCard = cards.element(boundBy: 0)
        XCTAssertLessThanOrEqual(firstCard.frame.minY - field.frame.maxY, 18, "Filter and cards should form a compact stack")
        let capture = app.buttons["island.clipboard.capture"]
        XCTAssertLessThanOrEqual(capture.frame.minY - firstCard.frame.maxY, 24, "Footer should sit directly below the shelf")
        XCTAssertLessThanOrEqual(capture.frame.maxY, element("island.panel", in: app).frame.maxY - 8)
        let compactProof = XCTAttachment(screenshot: element("island.panel", in: app).screenshot())
        compactProof.name = "Compact clipboard shelf and readable paused status"
        compactProof.lifetime = .keepAlways
        add(compactProof)
        let secondID = cards.element(boundBy: 1).identifier
        field.typeKey(.rightArrow, modifierFlags: [])
        field.typeKey(.return, modifierFlags: [])
        let shelfStatus = element("island.clipboard.status", in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@ OR value == %@", "Copied", "Copied"), object: shelfStatus)], timeout: 3), .completed)
        XCTAssertTrue(app.buttons[secondID].exists)
        field.typeText("Project notes")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "island.clipboard.restore.")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let restoreIdentifier = result.identifier
        let id = String(restoreIdentifier.dropFirst("island.clipboard.restore.".count))
        field.typeKey(.return, modifierFlags: [])
        let status = element("island.clipboard.status", in: app)
        let copied = NSPredicate(format: "label == %@ OR value == %@", "Copied", "Copied")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: copied, object: status)], timeout: 3), .completed)
        XCTAssertTrue(field.exists, "Restoring must not close or paste into another app")
        // The same UUID remains in the window: restore must not create a duplicate.
        field.typeKey(.escape, modifierFlags: [])
        element("navigation.clipboard", in: app).click()
        XCTAssertTrue(app.buttons["clipboard.restore.\(id)"].waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Open Island"].click()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Project notes")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.rightClick()
        app.menuItems["Delete item"].click()
        XCTAssertTrue(result.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("island.clipboard.empty", in: app).waitForExistence(timeout: 3))
        app.buttons["island.search.clear"].click()
        let image = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "island.clipboard.restore.", "Image")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        image.click()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: copied, object: status)], timeout: 3), .completed)
        let proof = XCTAttachment(screenshot: element("island.panel", in: app).screenshot())
        proof.name = "Island shared clipboard"
        proof.lifetime = .keepAlways
        add(proof)
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.buttons["clipboard.restore.\(id)"].exists)
    }

    @MainActor
    func testIslandKeyboardFocusAndEscape() throws {
        let app = launch(reset: true)
        app.menuBars.menuBarItems["View"].click()
        let open = app.menuItems["Open Island"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.click()
        let field = app.textFields["island.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("island focus")
        XCTAssertEqual(field.value as? String, "island focus")
        let proof = XCTAttachment(screenshot: element("island.panel", in: app).screenshot())
        proof.name = "Island black panel"
        proof.lifetime = .keepAlways
        add(proof)
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        // The main window receives keyboard commands again after the panel closes.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element("history.metric", in: app).waitForExistence(timeout: 3))
        app.terminate()
    }

    @MainActor
    func testAccessibilityAuditAcrossMainSections() throws {
        let app = launch(reset: true)
        let auditTypes: XCUIAccessibilityAuditType = [
            .contrast,
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .action,
            .parentChild
        ]

        try performAccessibilityAudit(in: app, for: auditTypes)
        for section in ["sensors", "network", "scroll", "dock", "settings"] {
            element("navigation.\(section)", in: app).click()
            try performAccessibilityAudit(in: app, for: auditTypes)
        }
        app.terminate()
    }

    @MainActor
    private func performAccessibilityAudit(
        in app: XCUIApplication,
        for auditTypes: XCUIAccessibilityAuditType
    ) throws {
        try app.performAccessibilityAudit(for: auditTypes) { issue in
            guard let element = issue.element else {
                return false
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
                && ["settings.language", "metrics.interval"].contains(element.identifier)
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
            return isLayoutGroup || isSidebarNavigationLink || isNativePickerAction
                || isWindowControlContainer || isSystemTouchBar
                || isNativeSidebarSelectionContrast
        }
    }

    @MainActor
    func testNavigationAndEmptyStates() throws {
        let app = launch(reset: true)
        XCTAssertTrue(app.staticTexts["System overview"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("history.empty", in: app).exists)
        capture("Overview EN", app: app)
        XCTAssertTrue(element("navigation.clipboard", in: app).exists)
        XCTAssertFalse(app.staticTexts["Sensors"].exists)
        element("navigation.network", in: app).click()
        XCTAssertTrue(app.staticTexts["Network"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("network.unavailable", in: app).exists)
        element("navigation.scroll", in: app).click()
        XCTAssertTrue(app.staticTexts["Scroll customization"].waitForExistence(timeout: 5))
        element("navigation.dock", in: app).click()
        XCTAssertTrue(app.staticTexts["Dock customization"].waitForExistence(timeout: 5))
        app.buttons["toolbar.settings"].click()
        XCTAssertTrue(element("settings.language", in: app).waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["System overview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["overview.openNetwork"].exists)
        element("navigation.network", in: app).click()
        XCTAssertTrue(element("network.unavailable", in: app).waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testLanguageChangesImmediatelyAndPersists() throws {
        var app = launch(reset: true)
        app.typeKey(",", modifierFlags: .command)
        let picker = element("settings.language", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        XCTAssertTrue(app.menuItems["Polski"].waitForExistence(timeout: 5))
        app.menuItems["Polski"].click()
        XCTAssertTrue(app.staticTexts["Ustawienia aplikacji"].waitForExistence(timeout: 5))
        capture("Settings PL", app: app)
        element("navigation.network", in: app).click()
        XCTAssertTrue(app.staticTexts["Połączenia sieciowe"].waitForExistence(timeout: 5))
        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(app.staticTexts["Przegląd systemu"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ostatnie 5 minut"].exists)
        capture("History PL", app: app)
        app.terminate()
    }

    @MainActor
    func testLiveMetricsAndSamplingPreference() throws {
        var app = launch(reset: true, liveMetrics: true)
        let current = NSPredicate(format: "value == %@", "Current")
        expectation(for: current, evaluatedWith: app.staticTexts["metric.cpu.status"])
        waitForExpectations(timeout: 12)
        XCTAssertNotEqual(app.staticTexts["metric.cpu.value"].value as? String, "-")
        let powerStatus = app.staticTexts["metric.power.status"].value as? String
        if powerStatus == "Current" {
            XCTAssertNotEqual(app.staticTexts["metric.power.value"].value as? String, "-")
        } else {
            XCTAssertEqual(powerStatus, "Unavailable")
            XCTAssertEqual(app.staticTexts["metric.power.value"].value as? String, "-")
        }
        XCTAssertTrue(element("history.summary", in: app).waitForExistence(timeout: 5))
        let metricPicker = element("history.metric", in: app)
        metricPicker.radioButtons["RAM"].click()
        XCTAssertTrue(element("history.summary", in: app).exists)
        capture("RAM history EN", app: app)
        metricPicker.radioButtons["Power"].click()
        if powerStatus == "Current" {
            XCTAssertTrue(element("history.summary", in: app).waitForExistence(timeout: 5))
        } else {
            XCTAssertTrue(element("history.empty", in: app).exists)
            XCTAssertFalse(element("history.summary", in: app).exists)
        }
        metricPicker.radioButtons["CPU"].click()
        XCTAssertTrue(element("history.summary", in: app).exists)
        capture("CPU history EN", app: app)
        app.typeKey(",", modifierFlags: .command)
        element("metrics.interval", in: app).click()
        app.menuItems["5 s"].click()
        app.terminate()
        app = launch(reset: false)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertEqual(element("metrics.interval", in: app).value as? String, "5 s")
        app.terminate()
    }

    @MainActor
    func testScrollPermissionDenialAndPreferencePersistence() throws {
        var app = launch(reset: true)
        element("navigation.scroll", in: app).click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Off")
        element("scroll.enabled", in: app).click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Inactive · Accessibility access required")
        XCTAssertTrue(app.buttons["scroll.permission"].exists)
        capture("Scroll permission EN", app: app)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["System overview"].exists)
        app.terminate()
        app = launch(reset: false)
        element("navigation.scroll", in: app).click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Inactive · Accessibility access required")
        element("scroll.enabled", in: app).click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Off")
        app.terminate()
    }

    @MainActor
    func testScrollEnabledStateWithPermissionFixture() throws {
        var app = launch(reset: true, scrollPermission: true)
        element("navigation.scroll", in: app).click()
        element("scroll.enabled", in: app).click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Active")
        XCTAssertFalse(app.buttons["scroll.permission"].exists)
        capture("Scroll active EN", app: app)
        app.terminate()
        app = launch(reset: false, scrollPermission: true)
        element("navigation.scroll", in: app).click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Active")
        element("scroll.enabled", in: app).click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Off")
        app.terminate()
    }

    @MainActor
    func testScrollInputMonitoringPermissionInPolish() throws {
        let app = launch(reset: true, inputMonitoringRequired: true)
        element("navigation.scroll", in: app).click()
        element("scroll.enabled", in: app).click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Inactive · Input Monitoring access required")
        XCTAssertEqual(app.buttons["scroll.permission"].label, "Open Input Monitoring")
        element("navigation.settings", in: app).click()
        element("settings.language", in: app).click()
        XCTAssertTrue(app.menuItems["Polski"].waitForExistence(timeout: 5))
        app.menuItems["Polski"].click()
        element("navigation.scroll", in: app).click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Nieaktywne · wymagane Monitorowanie wprowadzania")
        XCTAssertEqual(app.buttons["scroll.permission"].label, "Otwórz Monitorowanie wprowadzania")
        capture("Scroll input permission PL", app: app)
        app.terminate()
    }

    @MainActor
    func testMenuBarValuesAreOptionalAndPersist() throws {
        var app = launch(reset: true)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertFalse(element("menuBar.showCPU", in: app).exists)
        element("navigation.dock", in: app).click()
        let cpu = element("menuBar.showCPU", in: app)
        let gpu = element("menuBar.showGPU", in: app)
        let ram = element("menuBar.showRAM", in: app)
        let power = element("menuBar.showPower", in: app)
        XCTAssertEqual(switchValue(cpu), 0)
        XCTAssertEqual(switchValue(gpu), 0)
        XCTAssertEqual(switchValue(ram), 0)
        XCTAssertEqual(switchValue(power), 0)
        XCTAssertTrue(cpu.isHittable)
        XCTAssertTrue(gpu.isHittable)
        XCTAssertTrue(ram.isHittable)
        XCTAssertTrue(power.isHittable)
        cpu.click()
        gpu.click()
        ram.click()
        power.click()
        XCTAssertEqual(switchValue(cpu), 1)
        XCTAssertEqual(switchValue(gpu), 1)
        XCTAssertEqual(switchValue(ram), 1)
        XCTAssertEqual(switchValue(power), 1)
        for id in ["CPUTemperature", "GPUTemperature", "Fans"] {
            let toggle = element("menuBar.show" + id, in: app)
            XCTAssertEqual(switchValue(toggle), 0)
            toggle.click()
            XCTAssertEqual(switchValue(toggle), 1)
        }
        let status = app.menuBars.statusItems.matching(
            NSPredicate(format: "title CONTAINS %@ OR label CONTAINS %@", "CPU temperature", "CPU temperature")
        ).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(status.frame.width, 150)
        app.terminate()

        app = launch(reset: false)
        element("navigation.dock", in: app).click()
        XCTAssertEqual(switchValue(element("menuBar.showCPU", in: app)), 1)
        XCTAssertEqual(switchValue(element("menuBar.showGPU", in: app)), 1)
        XCTAssertEqual(switchValue(element("menuBar.showRAM", in: app)), 1)
        XCTAssertEqual(switchValue(element("menuBar.showPower", in: app)), 1)
        for id in ["CPUTemperature", "GPUTemperature", "Fans"] {
            XCTAssertEqual(switchValue(element("menuBar.show" + id, in: app)), 1)
        }
        app.terminate()
    }

    @MainActor
    func testDockPreferenceAndWindowReopenBehavior() throws {
        var app = launch(reset: true)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertFalse(element("integration.showDockIcon", in: app).exists)
        element("navigation.dock", in: app).click()
        XCTAssertTrue(element("settings.dock.content", in: app).waitForExistence(timeout: 5))
        let dockToggle = element("integration.showDockIcon", in: app)
        XCTAssertEqual(switchValue(dockToggle), 1)
        dockToggle.click()
        XCTAssertEqual(switchValue(dockToggle), 0)
        app.terminate()

        app = launch(reset: false, expectsWindow: false)
        app.activate()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(waitForWindow(in: app, exists: true))
        element("navigation.dock", in: app).click()
        let persistedDockToggle = element("integration.showDockIcon", in: app)
        XCTAssertEqual(switchValue(persistedDockToggle), 0)
        persistedDockToggle.click()
        XCTAssertEqual(switchValue(persistedDockToggle), 1)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForWindow(in: app, exists: false))
        app.activate()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(waitForWindow(in: app, exists: true))
        XCTAssertTrue(app.staticTexts["System overview"].waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testLaunchAtLoginStateAndPreferencePersistence() throws {
        var app = launch(reset: true)
        app.typeKey(",", modifierFlags: .command)
        let settingsScrollView = app.scrollViews.element(boundBy: 1)
        settingsScrollView.scroll(byDeltaX: 0, deltaY: 120)
        let toggle = element("integration.launchAtLogin", in: app)
        XCTAssertEqual(switchValue(toggle), 1)
        XCTAssertTrue(app.staticTexts["On in macOS"].exists)
        toggle.click()
        XCTAssertEqual(switchValue(toggle), 0)
        XCTAssertTrue(app.staticTexts["Off in macOS"].exists)
        app.terminate()

        app = launch(reset: false)
        app.typeKey(",", modifierFlags: .command)
        app.scrollViews.element(boundBy: 1).scroll(byDeltaX: 0, deltaY: 120)
        XCTAssertEqual(switchValue(element("integration.launchAtLogin", in: app)), 0)
        XCTAssertTrue(app.staticTexts["Off in macOS"].exists)
        app.terminate()

        app = launch(reset: true, loginItemRequiresApproval: true)
        app.typeKey(",", modifierFlags: .command)
        app.scrollViews.element(boundBy: 1).scroll(byDeltaX: 0, deltaY: 120)
        XCTAssertTrue(app.staticTexts["Approval required in macOS"].exists)
        XCTAssertTrue(app.buttons["integration.launchAtLogin.openSettings"].exists)
        app.terminate()
    }

    @MainActor
    func testLoginLaunchStaysInBackgroundAndProvidesMenuBar() throws {
        let app = launch(reset: true, liveMetrics: true, launchedAtLogin: true, expectsWindow: false)
        XCTAssertFalse(app.windows.firstMatch.waitForExistence(timeout: 2))
        let statusItem = app.menuBars.statusItems["Mac Manager"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        let panel = element("menuBar.panel", in: app)
        statusItem.click()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let openButton = app.buttons["Open window"]
        let quitButton = app.buttons["Quit"]
        XCTAssertTrue(openButton.isHittable)
        XCTAssertTrue(quitButton.isHittable)
        XCTAssertFalse(app.buttons["island.menuBar.open"].exists)
        XCTAssertFalse(app.buttons["Settings"].exists)
        XCTAssertFalse(app.staticTexts["Mouse scrolling"].exists)
        XCTAssertEqual(openButton.frame.width, quitButton.frame.width, accuracy: 1)
        openButton.click()
        XCTAssertTrue(waitForElement(panel, exists: false))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        let current = NSPredicate(format: "value == %@", "Current")
        let status = app.staticTexts["metric.cpu.status"]
        let currentExpectation = XCTNSPredicateExpectation(predicate: current, object: status)
        let result = XCTWaiter.wait(for: [currentExpectation], timeout: 12)
        XCTAssertEqual(result, .completed, "CPU status after login launch: \(String(describing: status.value))")
        app.terminate()
    }

    @MainActor
    func testSensorsUnitsAndLiveReadings() throws {
        var length = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &length, nil, 0) == 0, length > 0 else {
            throw XCTSkip("Cannot identify reference hardware")
        }
        var bytes = [CChar](repeating: 0, count: length)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &length, nil, 0) == 0,
              String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self) == "Apple M4 Pro" else {
            throw XCTSkip("Temperature catalog currently covers Apple M4 Pro")
        }
        let app = launch(reset: true, liveMetrics: true)
        element("navigation.sensors", in: app).click()
        let cpu = element("sensors.temperature.cpu", in: app)
        XCTAssertTrue(cpu.waitForExistence(timeout: 5))
        let celsius = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "°C", "°C")
        let ready = XCTNSPredicateExpectation(predicate: celsius, object: cpu)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 12), .completed)
        let gpu = element("sensors.temperature.gpu", in: app)
        XCTAssertTrue((gpu.value as? String ?? gpu.label).contains("°C"))
        let fan = element("sensors.fan.0", in: app)
        XCTAssertTrue((fan.value as? String ?? fan.label).contains("RPM"))
        XCTAssertTrue(element("sensors.history.temperatureChart", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("sensors.history.fanChart", in: app).exists)
        let temperatureSelection = element("sensors.history.temperatureSelection", in: app)
        XCTAssertTrue(temperatureSelection.exists)
        app.radioButtons["°F"].click()
        XCTAssertTrue((cpu.value as? String ?? cpu.label).contains("°F"))
        app.terminate()
        let restored = launch(reset: false, liveMetrics: true)
        element("navigation.sensors", in: restored).click()
        let fahrenheit = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "°F", "°F"),
            object: element("sensors.temperature.cpu", in: restored))
        XCTAssertEqual(XCTWaiter.wait(for: [fahrenheit], timeout: 12), .completed)
        restored.terminate()
    }

    @MainActor
    func testUpdateSettingsCacheAndLocalDiagnostics() throws {
        var app = launch(reset: true, updateFixture: .available)
        app.typeKey(",", modifierFlags: .command)
        let status = element("updates.status", in: app)
        scrollTo(status, in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "Version 0.9.0 is available")
        XCTAssertTrue(app.buttons["updates.openRelease"].exists)

        let alignedControls = [
            element("settings.language", in: app),
            element("metrics.interval", in: app),
            element("integration.launchAtLogin", in: app),
            element("updates.automatic", in: app)
        ]
        for control in alignedControls {
            XCTAssertTrue(control.exists)
            XCTAssertEqual(control.frame.maxX, alignedControls[0].frame.maxX, accuracy: 1)
        }

        let automatic = element("updates.automatic", in: app)
        XCTAssertEqual(switchValue(automatic), 1)
        automatic.click()
        XCTAssertEqual(switchValue(automatic), 0)

        let copy = app.buttons["diagnostics.copy"]
        scrollTo(copy, in: app)
        XCTAssertTrue(copy.isHittable)
        copy.click()
        let report = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertTrue(report.contains("Mac Manager Diagnostic Report"))
        XCTAssertTrue(report.contains("architecture: arm64"))
        XCTAssertTrue(report.contains("update_status: updateAvailable"))
        XCTAssertFalse(report.contains("source_ip"))
        app.terminate()

        app = launch(reset: false, updateFixture: .available)
        app.typeKey(",", modifierFlags: .command)
        let restoredAutomatic = element("updates.automatic", in: app)
        scrollTo(restoredAutomatic, in: app)
        XCTAssertEqual(switchValue(restoredAutomatic), 0)
        XCTAssertEqual(
            element("updates.status", in: app).value as? String,
            "Version 0.9.0 is available"
        )
        app.terminate()
    }

    @MainActor
    func testUpdateCurrentNoReleaseFailureAndOfflineStates() throws {
        for (fixture, expected) in [
            (UpdateFixture.current, "You have the latest public version"),
            (.noRelease, "No compatible public release"),
            (.failure, "GitHub did not respond in time"),
            (.offline, "No internet connection")
        ] {
            let app = launch(reset: true, updateFixture: fixture)
            app.typeKey(",", modifierFlags: .command)
            let status = element("updates.status", in: app)
            scrollTo(status, in: app)
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            let predicate = NSPredicate(format: "value == %@", expected)
            expectation(for: predicate, evaluatedWith: status)
            waitForExpectations(timeout: 8)
            XCTAssertFalse(app.buttons["updates.openRelease"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testAvailableUpdateAndDiagnosticsLocalizeToPolish() throws {
        let app = launch(reset: true, updateFixture: .available)
        app.typeKey(",", modifierFlags: .command)
        let picker = element("settings.language", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        XCTAssertTrue(app.menuItems["Polski"].waitForExistence(timeout: 5))
        app.menuItems["Polski"].click()
        XCTAssertTrue(app.staticTexts["Ustawienia aplikacji"].waitForExistence(timeout: 5))

        let status = element("updates.status", in: app)
        scrollTo(status, in: app)
        XCTAssertEqual(status.value as? String, "Dostępna jest wersja 0.9.0")
        XCTAssertEqual(app.buttons["updates.openRelease"].label, "Otwórz wydanie")

        let copy = app.buttons["diagnostics.copy"]
        scrollTo(copy, in: app)
        XCTAssertEqual(copy.label, "Kopiuj raport")
        app.terminate()
    }

    @MainActor
    func testClipboardSearchRestoreRetentionAndClear() throws {
        let app = launch(reset: true, clipboardFixture: true)
        element("navigation.clipboard", in: app).click()
        let search = app.textFields["clipboard.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "clipboard.restore.")).firstMatch.waitForExistence(timeout: 5))
        search.click()
        search.typeText("project")
        let restore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "clipboard.restore.")).firstMatch
        restore.click()
        XCTAssertTrue(app.buttons["Ready to paste"].waitForExistence(timeout: 5))
        app.buttons["clipboard.options"].click()
        let limit = app.textFields["clipboard.limit.count"]
        XCTAssertTrue(limit.waitForExistence(timeout: 5))
        limit.click(); limit.typeKey("a", modifierFlags: .command); limit.typeText("1")
        app.buttons["clipboard.settings.save"].click()
        XCTAssertTrue(app.sheets.buttons["action-button-1"].waitForExistence(timeout: 5))
        app.sheets.buttons["action-button-1"].click()
        XCTAssertTrue(app.staticTexts["No matching text"].waitForExistence(timeout: 5))
        search.click(); search.typeKey("a", modifierFlags: .command); search.typeKey(.delete, modifierFlags: [])
        app.buttons["clipboard.clear"].click()
        app.sheets.buttons["action-button-1"].click()
        XCTAssertTrue(app.staticTexts["No saved copies yet"].waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testClipboardDefaultsOffAndLocalizes() throws {
        let app = launch(reset: true)
        element("navigation.clipboard", in: app).click()
        XCTAssertTrue(app.buttons["clipboard.enable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["History is off"].exists)
        element("navigation.settings", in: app).click()
        app.popUpButtons["settings.language"].click()
        app.menuItems["Polski"].click()
        element("navigation.clipboard", in: app).click()
        XCTAssertEqual(app.buttons["clipboard.enable"].label, "Włącz historię")
        XCTAssertTrue(app.staticTexts["Historia jest wyłączona"].exists)
        app.terminate()
    }

    @MainActor
    func testLauncherSearchEscapeAndNavigation() throws {
        let app = launch(reset: true)
        element("navigation.settings", in: app).click()
        app.buttons["launcher.open"].click()
        let field = app.textFields["launcher.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click(); field.typeText("netw")
        XCTAssertTrue(app.buttons["launcher.result.command:network"].waitForExistence(timeout: 5))
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(field.value as? String, "")
        field.typeText("siec")
        XCTAssertTrue(app.buttons["launcher.result.command:network"].waitForExistence(timeout: 5))
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("network.unavailable", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists)
        element("navigation.settings", in: app).click()
        app.buttons["launcher.open"].click()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(field.exists)
        app.terminate()
    }

    @MainActor
    func testLauncherGlobalShortcutHiddenWindowAndApplicationLaunch() throws {
        let app = launch(reset: true, launcherLiveTesting: true)
        app.windows["main"].buttons["_XCUI:CloseWindow"].click()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("q", modifierFlags: [.option])
        let field = app.textFields["launcher.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.windows["main"].exists)
        field.typeText("calculator")
        let result = app.buttons["launcher.result.app:com.apple.calculator"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        let wasRunning = calculator.state != .notRunning
        result.click()
        XCTAssertTrue(calculator.wait(for: .runningForeground, timeout: 10))
        XCTAssertFalse(field.exists)
        if !wasRunning { calculator.terminate() }
        finder.activate()
        finder.typeKey("q", modifierFlags: [.option])
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("settings")
        let settings = app.buttons["launcher.result.command:settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()
        XCTAssertTrue(app.buttons["launcher.open"].waitForExistence(timeout: 5))
        app.popUpButtons["launcher.key"].click()
        app.menuItems["K"].click()
        XCTAssertEqual(app.popUpButtons["launcher.key"].value as? String, "K")
        app.popUpButtons["launcher.key"].click()
        app.menuItems["Space"].click()
        app.popUpButtons["launcher.modifiers"].click()
        app.menuItems["⌥"].click()
        XCTAssertEqual(app.popUpButtons["launcher.modifiers"].value as? String, "⌥")
        XCTAssertFalse(app.staticTexts["Shortcut unavailable. Previous binding was kept, if active. Choose another combination."].exists)
        app.windows["main"].buttons["_XCUI:CloseWindow"].click()
        finder.activate()
        finder.typeKey(" ", modifierFlags: [.option])
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(field.exists)
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
        app.terminate()
    }

    @MainActor
    func testLauncherCalculatorAndSharedClipboardMode() throws {
        let app = launch(reset: true, clipboardFixture: true)
        defer { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
        app.buttons["launcher.open"].click()
        let field = app.textFields["launcher.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("2+3*4")
        let result = app.buttons["launcher.result.calculator:result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("14"), result.debugDescription)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(field.exists)
        app.buttons["launcher.open"].click()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeKey(.tab, modifierFlags: [])
        field.typeText("Project notes")
        let clipboardResult = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "launcher.result.clipboard:")).firstMatch
        XCTAssertTrue(clipboardResult.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(field.exists)
        app.buttons["launcher.open"].click()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Project notes")
        XCTAssertFalse(clipboardResult.exists)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(clipboardResult.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(field.exists)
    }

    @MainActor
    func testLauncherRestoresSearchFocusAfterMenuAndCustomization() throws {
        let app = launch(reset: true)
        defer { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
        app.buttons["launcher.open"].click()
        let field = app.textFields["launcher.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("net")
        let result = app.buttons["launcher.result.command:network"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.rightClick()
        XCTAssertTrue(app.menuItems["Customize"].waitForExistence(timeout: 5))
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.menuItems["Customize"].waitForNonExistence(timeout: 3))
        field.typeText("work")
        XCTAssertEqual(field.value as? String, "network")
        field.typeKey(.leftArrow, modifierFlags: [])
        result.rightClick()
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.menuItems["Customize"].waitForNonExistence(timeout: 3))
        field.typeText("x")
        XCTAssertEqual(field.value as? String, "networxk", "Menu dismissal must preserve the insertion point")
        field.typeKey("a", modifierFlags: .command)
        field.typeText("network")
        result.rightClick()
        app.menuItems["Customize"].click()
        let alias = app.textFields["launcher.alias"]
        XCTAssertTrue(alias.waitForExistence(timeout: 5))
        alias.click(); alias.typeText("net-alias")
        XCTAssertEqual(alias.value as? String, "net-alias")
        app.buttons["Cancel"].click()
        XCTAssertTrue(alias.waitForNonExistence(timeout: 3))
        field.typeText("s")
        XCTAssertEqual(field.value as? String, "networks")
        field.typeKey(.escape, modifierFlags: [])
        field.typeText("net")
        XCTAssertEqual(field.value as? String, "net")
        result.rightClick()
        app.menuItems["Customize"].click()
        XCTAssertTrue(alias.waitForExistence(timeout: 5))
        app.buttons["Save"].click()
        XCTAssertTrue(alias.waitForNonExistence(timeout: 3))
        field.typeText("work")
        XCTAssertEqual(field.value as? String, "network")
    }

    @MainActor
    func testLauncherAliasFavoriteAndShortcutConflict() throws {
        let app = launch(reset: true, launcherLiveTesting: true)
        defer { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
        app.buttons["launcher.open"].click()
        let field = app.textFields["launcher.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("network")
        let result = app.buttons["launcher.result.command:network"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.rightClick()
        app.menuItems["Customize"].click()
        let alias = app.textFields["launcher.alias"]
        XCTAssertTrue(alias.waitForExistence(timeout: 5))
        alias.click(); alias.typeText("myconnection")
        app.checkBoxes["Favorite"].click()
        let popover = app.popovers.firstMatch
        popover.checkBoxes["Enable global shortcut"].click()
        app.buttons["Save"].click()
        XCTAssertTrue(alias.exists, "Conflicting palette shortcut must keep the editor open")
        app.popUpButtons["launcher.itemKey"].click()
        app.menuItems["N"].click()
        app.buttons["Save"].click()
        field.click(); field.typeKey("a", modifierFlags: .command); field.typeText("myconnection")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("network.unavailable", in: app).waitForExistence(timeout: 5))
        app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("n", modifierFlags: [.control, .option])
        XCTAssertTrue(element("network.unavailable", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func launch(
        reset: Bool,
        liveMetrics: Bool = false,
        clipboardFixture: Bool = false,
        islandClipboardFixture: Bool = false,
        islandDenseClipboardFixture: Bool = false,
        islandReduceMotion: Bool = false,
        islandConstrainedLayout: Bool = false,
        musicDenied: Bool = false,
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
        if islandClipboardFixture { app.launchArguments.append("--island-clipboard-fixture") }
        if islandDenseClipboardFixture { app.launchArguments.append("--island-dense-clipboard-fixture") }
        if islandReduceMotion { app.launchArguments.append("--island-reduce-motion") }
        if islandConstrainedLayout { app.launchArguments.append("--island-constrained-layout") }
        if musicDenied { app.launchArguments.append("--music-denied") }
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

    private enum UpdateFixture {
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
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func switchValue(_ element: XCUIElement) -> Int? {
        if let number = element.value as? NSNumber { return number.intValue }
        if let text = element.value as? String { return Int(text) }
        return nil
    }

    @MainActor
    private func scrollTo(_ target: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews["main.detailScroll"]
        for _ in 0..<10 where !target.isHittable {
            scrollView.scroll(byDeltaX: 0, deltaY: -300)
        }
    }

    @MainActor
    private func waitForWindow(in app: XCUIApplication, exists: Bool) -> Bool {
        let predicate = NSPredicate(format: "exists == %@", NSNumber(value: exists))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.windows.firstMatch)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func waitForElement(_ element: XCUIElement, exists: Bool) -> Bool {
        let predicate = NSPredicate(format: "exists == %@", NSNumber(value: exists))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
