import AppKit
import XCTest

final class AppShellTests: XCTestCase {
    @MainActor
    func testNavigationAndEmptyStates() throws {
        let app = launch(reset: true)
        XCTAssertTrue(app.staticTexts["System overview"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("history.empty", in: app).exists)
        capture("Overview EN", app: app)
        XCTAssertTrue(element("metrics.unavailable", in: app).exists)
        XCTAssertFalse(app.staticTexts["Clipboard"].exists)
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
        app.buttons["overview.openNetwork"].click()
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
        XCTAssertEqual(app.staticTexts["metric.power.status"].value as? String, "Unavailable")
        XCTAssertEqual(app.staticTexts["metric.power.value"].value as? String, "-")
        XCTAssertTrue(element("history.summary", in: app).waitForExistence(timeout: 5))
        let metricPicker = element("history.metric", in: app)
        metricPicker.radioButtons["RAM"].click()
        XCTAssertTrue(element("history.summary", in: app).exists)
        capture("RAM history EN", app: app)
        metricPicker.radioButtons["Power"].click()
        XCTAssertTrue(element("history.empty", in: app).exists)
        XCTAssertFalse(element("history.summary", in: app).exists)
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
        let ram = element("menuBar.showRAM", in: app)
        let power = element("menuBar.showPower", in: app)
        XCTAssertEqual(switchValue(cpu), 0)
        XCTAssertEqual(switchValue(ram), 0)
        XCTAssertEqual(switchValue(power), 0)
        XCTAssertTrue(cpu.isHittable)
        XCTAssertTrue(ram.isHittable)
        XCTAssertTrue(power.isHittable)
        cpu.click()
        ram.click()
        power.click()
        XCTAssertEqual(switchValue(cpu), 1)
        XCTAssertEqual(switchValue(ram), 1)
        XCTAssertEqual(switchValue(power), 1)
        app.terminate()

        app = launch(reset: false)
        element("navigation.dock", in: app).click()
        XCTAssertEqual(switchValue(element("menuBar.showCPU", in: app)), 1)
        XCTAssertEqual(switchValue(element("menuBar.showRAM", in: app)), 1)
        XCTAssertEqual(switchValue(element("menuBar.showPower", in: app)), 1)
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
        statusItem.click()
        XCTAssertTrue(statusItem.exists)
        statusItem.click()
        app.activate()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        let current = NSPredicate(format: "value == %@", "Current")
        expectation(for: current, evaluatedWith: app.staticTexts["metric.cpu.status"])
        waitForExpectations(timeout: 12)
        app.terminate()
    }

    @MainActor
    func testUpdateSettingsCacheAndLocalDiagnostics() throws {
        var app = launch(reset: true, updateAvailable: true)
        app.typeKey(",", modifierFlags: .command)
        let status = element("updates.status", in: app)
        scrollTo(status, in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "Version 0.2.0 is available")
        XCTAssertTrue(app.buttons["updates.openRelease"].exists)

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

        app = launch(reset: false, updateAvailable: true)
        app.typeKey(",", modifierFlags: .command)
        let restoredAutomatic = element("updates.automatic", in: app)
        scrollTo(restoredAutomatic, in: app)
        XCTAssertEqual(switchValue(restoredAutomatic), 0)
        XCTAssertEqual(
            element("updates.status", in: app).value as? String,
            "Version 0.2.0 is available"
        )
        app.terminate()
    }

    @MainActor
    private func launch(
        reset: Bool,
        liveMetrics: Bool = false,
        scrollPermission: Bool = false,
        inputMonitoringRequired: Bool = false,
        loginItemRequiresApproval: Bool = false,
        launchedAtLogin: Bool = false,
        updateAvailable: Bool = false,
        expectsWindow: Bool = true
    ) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if reset { app.launchArguments.append("--reset-preferences") }
        if liveMetrics { app.launchArguments.append("--live-metrics") }
        if scrollPermission { app.launchArguments.append("--scroll-permission-granted") }
        if inputMonitoringRequired { app.launchArguments.append("--scroll-input-monitoring-required") }
        if loginItemRequiresApproval { app.launchArguments.append("--login-item-requires-approval") }
        if launchedAtLogin { app.launchArguments.append("--launched-at-login") }
        if updateAvailable { app.launchArguments.append("--update-available") }
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
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.element(boundBy: 1)
        for _ in 0..<10 where !element.isHittable {
            scrollView.scroll(byDeltaX: 0, deltaY: 300)
        }
    }

    @MainActor
    private func waitForWindow(in app: XCUIApplication, exists: Bool) -> Bool {
        let predicate = NSPredicate(format: "exists == %@", NSNumber(value: exists))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.windows.firstMatch)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
