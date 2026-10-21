import AppKit
import XCTest

final class LauncherTests: AppUITestSupport {
    @MainActor
    func testLauncherSearchEscapeAndNavigation() throws {
        let app = launch(reset: true)
        element("navigation.settings", in: app).click()
        app.buttons["launcher.open"].click()
        let field = app.textFields["launcher.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click(); field.typeText("netw")
        XCTAssertTrue(app.buttons["launcher.result.system:com.apple.Network-Settings.extension"].waitForExistence(timeout: 5))
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(field.value as? String, "")
        field.typeText("siec")
        let network = app.buttons["launcher.result.system:com.apple.Network-Settings.extension"]
        XCTAssertTrue(network.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: network)], timeout: 5), .completed)
        // System and application providers can both match the Polish query.
        // Navigate to the intended row instead of assuming its ranking position.
        for _ in 0..<40 {
            if network.isSelected { break }
            field.typeKey(.downArrow, modifierFlags: [])
        }
        XCTAssertTrue(network.isSelected)
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.systempreferences").wait(for: .runningForeground, timeout: 5))
        XCTAssertFalse(field.exists)
        app.activate()
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
        let settings = app.buttons["launcher.result.app:com.apple.systempreferences"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.systempreferences").wait(for: .runningForeground, timeout: 5))
        app.activate()
        app.typeKey(",", modifierFlags: .command)
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
        let result = app.buttons["launcher.result.system:com.apple.Network-Settings.extension"]
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
        let result = app.buttons["launcher.result.system:com.apple.Network-Settings.extension"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.rightClick()
        app.menuItems["Customize"].click()
        let alias = app.textFields["launcher.alias"]
        XCTAssertTrue(alias.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["launcher.customization.title"].value as? String, "Network")
        alias.click(); alias.typeText("myconnection")
        app.checkBoxes["Favorite"].click()
        let popover = app.popovers.firstMatch
        popover.checkBoxes["Enable global shortcut"].click()
        app.buttons["Save"].click()
        XCTAssertTrue(alias.exists, "Conflicting palette shortcut must keep the editor open")
        popover.popUpButtons["launcher.modifiers"].click()
        app.menuItems["⌥"].click()
        app.popUpButtons["launcher.itemKey"].click()
        app.menuItems["N"].click()
        app.buttons["Save"].click()
        XCTAssertTrue(alias.waitForNonExistence(timeout: 3), "Saving the chosen shortcut must close the editor")
        field.click(); field.typeKey("a", modifierFlags: .command); field.typeText("myconnection")
        XCTAssertEqual(field.value as? String, "myconnection")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: result)], timeout: 5), .completed)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.systempreferences").wait(for: .runningForeground, timeout: 5))
        app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("n", modifierFlags: [.option])
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.systempreferences").wait(for: .runningForeground, timeout: 5))
    }

}

extension LauncherTests {
    @MainActor func testSettingsResultsExcludeMacManagerSections() throws {
        let app = launch(reset: true)
        defer { app.terminate() }
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Open launcher"].click()
        let field = app.textFields["launcher.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Settings")
        XCTAssertTrue(app.buttons["launcher.result.app:com.apple.systempreferences"].waitForExistence(timeout: 10))
        let internalSections = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "launcher.result.command:"))
        XCTAssertEqual(internalSections.count, 0)
        field.typeKey("a", modifierFlags: .command)
        field.typeText("network")
        XCTAssertTrue(app.buttons["launcher.result.system:com.apple.Network-Settings.extension"].waitForExistence(timeout: 5))
        XCTAssertEqual(internalSections.count, 0)
    }

    @MainActor func testQueryToVisibleResultBenchmark() throws {
        guard ProcessInfo.processInfo.environment["MM_UI_BENCHMARKS"] == "1" else {
            throw XCTSkip("Opt-in UI latency measurement; includes XCTest input and observation overhead")
        }
        let app = launch(reset: true)
        defer { app.terminate() }
        element("navigation.settings", in: app).click()
        app.buttons["launcher.open"].click()
        let field = app.textFields["launcher.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        measure(metrics: [XCTClockMetric()]) {
            field.typeKey("a", modifierFlags: .command)
            field.typeText("network")
            XCTAssertTrue(app.buttons["launcher.result.system:com.apple.Network-Settings.extension"].waitForExistence(timeout: 3))
            field.typeKey("a", modifierFlags: .command)
            field.typeText("settings")
            XCTAssertTrue(app.buttons["launcher.result.app:com.apple.systempreferences"].waitForExistence(timeout: 3))
        }
    }
}

extension LauncherTests {
    @MainActor func testShiftTabReachesModeControlAndReturnDoesNotRestoreSelection() throws {
        let app = launch(reset: true, clipboardFixture: true)
        defer { app.terminate() }
        element("navigation.settings", in: app).click()
        app.buttons["launcher.open"].click()
        let field = app.textFields["launcher.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeKey(.tab, modifierFlags: .shift)
        app.typeKey(.return, modifierFlags: [])
        let copy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "launcher.result.clipboard:")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        XCTAssertTrue(field.exists)
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(copy.waitForNonExistence(timeout: 3))
        app.typeKey(.tab, modifierFlags: [])
        field.typeText("network")
        XCTAssertTrue(app.buttons["launcher.result.system:com.apple.Network-Settings.extension"].waitForExistence(timeout: 3))
    }
}
