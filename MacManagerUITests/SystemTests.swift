import AppKit
import XCTest

final class SystemTests: AppUITestSupport {
    @MainActor
    func testRecoveredPreferencesAndLoginFailureRetryInBothLanguages() throws {
        let app = launch(reset: true, loginItemUnregisterFailsOnce: true, damagedPreferences: true)
        defer { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
        let notice = app.staticTexts["settings.recovered"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue((notice.value as? String ?? notice.label).contains("Some saved settings"))
        capture("Recovered preferences EN", app: app)
        let toggle = element("integration.launchAtLogin", in: app)
        scrollTo(toggle, in: app)
        XCTAssertEqual(switchValue(toggle), 1)
        toggle.click()
        XCTAssertEqual(switchValue(toggle), 1)
        let error = app.staticTexts["integration.launchAtLogin.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertTrue((error.value as? String ?? error.label).contains("Could not disable"))
        let retry = app.buttons["integration.launchAtLogin.retry"]
        scrollTo(retry, in: app)
        XCTAssertEqual(retry.label, "Retry")
        capture("Login failure EN", app: app)
        let language = element("settings.language", in: app)
        scrollTo(language, in: app)
        language.click()
        app.menuItems["Polski"].click()
        XCTAssertTrue((notice.value as? String ?? notice.label).contains("Część zapisanych ustawień"))
        capture("Recovered preferences PL", app: app)
        scrollTo(retry, in: app)
        XCTAssertTrue((error.value as? String ?? error.label).contains("Nie udało się wyłączyć"))
        XCTAssertEqual(retry.label, "Ponów próbę")
        capture("Login failure PL", app: app)
        retry.click()
        XCTAssertTrue(error.waitForNonExistence(timeout: 3))
        XCTAssertEqual(switchValue(toggle), 0)
    }

    @MainActor
    func testIndependentScrollAxesPersistAndLocalize() throws {
        var app = launch(reset: true, scrollPermission: true)
        defer { app.terminate() }
        element("navigation.scroll", in: app).click()
        element("scroll.enabled", in: app).click()
        let horizontal = app.checkBoxes["scroll.axis.horizontal"]
        let vertical = app.checkBoxes["scroll.axis.vertical"]
        XCTAssertTrue(horizontal.waitForExistence(timeout: 3))
        XCTAssertEqual(switchValue(horizontal), 1)
        XCTAssertEqual(switchValue(vertical), 1)
        XCTAssertEqual(horizontal.label, "Reverse horizontal mouse scrolling")
        horizontal.click()
        XCTAssertEqual(switchValue(horizontal), 0)
        XCTAssertEqual(switchValue(vertical), 1)
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Active")
        capture("Independent scroll axes EN", app: app)
        vertical.click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Off")
        XCTAssertEqual(switchValue(element("scroll.enabled", in: app)), 1)
        app.terminate()
        app = launch(reset: false, scrollPermission: true)
        element("navigation.scroll", in: app).click()
        XCTAssertEqual(switchValue(app.checkBoxes["scroll.axis.horizontal"]), 0)
        XCTAssertEqual(switchValue(app.checkBoxes["scroll.axis.vertical"]), 0)
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Off")
        app.checkBoxes["scroll.axis.vertical"].click()
        XCTAssertEqual(app.staticTexts["scroll.status"].value as? String, "Active")
        element("navigation.settings", in: app).click()
        element("settings.language", in: app).click()
        app.menuItems["Polski"].click()
        element("navigation.scroll", in: app).click()
        XCTAssertEqual(app.checkBoxes["scroll.axis.horizontal"].label, "Odwracaj przewijanie poziome myszy")
        app.checkBoxes["scroll.axis.vertical"].click()
        app.checkBoxes["scroll.axis.horizontal"].click()
        XCTAssertEqual(switchValue(app.checkBoxes["scroll.axis.vertical"]), 0)
        XCTAssertEqual(switchValue(app.checkBoxes["scroll.axis.horizontal"]), 1)
        capture("Independent scroll axes PL", app: app)
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
        let toggle = element("integration.launchAtLogin", in: app)
        scrollTo(toggle, in: app)
        XCTAssertEqual(switchValue(toggle), 1)
        XCTAssertTrue(app.staticTexts["On in macOS"].exists)
        toggle.click()
        XCTAssertEqual(switchValue(toggle), 0)
        XCTAssertTrue(app.staticTexts["Off in macOS"].exists)
        app.terminate()

        app = launch(reset: false)
        app.typeKey(",", modifierFlags: .command)
        scrollTo(element("integration.launchAtLogin", in: app), in: app)
        XCTAssertEqual(switchValue(element("integration.launchAtLogin", in: app)), 0)
        XCTAssertTrue(app.staticTexts["Off in macOS"].exists)
        app.terminate()

        app = launch(reset: true, loginItemRequiresApproval: true)
        app.typeKey(",", modifierFlags: .command)
        scrollTo(element("integration.launchAtLogin", in: app), in: app)
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

}
