import AppKit
import XCTest

final class SystemTests: AppUITestSupport {
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
