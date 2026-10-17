import AppKit
import XCTest

final class AppShellTests: AppUITestSupport {
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

}
