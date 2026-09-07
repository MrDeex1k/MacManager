import XCTest

final class AppShellTests: XCTestCase {
    @MainActor
    func testNavigationAndEmptyStates() throws {
        let app = launch(reset: true)
        XCTAssertTrue(app.staticTexts["System overview"].waitForExistence(timeout: 10))
        capture("Overview EN", app: app)
        XCTAssertTrue(element("metrics.unavailable", in: app).exists)
        XCTAssertFalse(app.staticTexts["Clipboard"].exists)
        XCTAssertFalse(app.staticTexts["Sensors"].exists)
        element("navigation.network", in: app).click()
        XCTAssertTrue(app.staticTexts["Network"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("network.unavailable", in: app).exists)
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
        app.menuItems["Polski"].click()
        XCTAssertTrue(app.staticTexts["Ustawienia aplikacji"].waitForExistence(timeout: 5))
        capture("Settings PL", app: app)
        element("navigation.network", in: app).click()
        XCTAssertTrue(app.staticTexts["Połączenia sieciowe"].waitForExistence(timeout: 5))
        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(app.staticTexts["Przegląd systemu"].waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor
    func testLiveMetricsAndSamplingPreference() throws {
        var app = launch(reset: true, liveMetrics: true)
        let current = NSPredicate(format: "value == %@", "Current")
        expectation(for: current, evaluatedWith: app.staticTexts["metric.cpu.status"])
        waitForExpectations(timeout: 12)
        XCTAssertNotEqual(app.staticTexts["metric.cpu.value"].value as? String, "—")
        XCTAssertEqual(app.staticTexts["metric.power.status"].value as? String, "Unavailable")
        XCTAssertEqual(app.staticTexts["metric.power.value"].value as? String, "—")
        capture("Live metrics EN", app: app)
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
    private func launch(reset: Bool, liveMetrics: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if reset { app.launchArguments.append("--reset-preferences") }
        if liveMetrics { app.launchArguments.append("--live-metrics") }
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
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
}
