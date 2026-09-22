import AppKit
import XCTest

final class AppShellTests: XCTestCase {
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
    private func launch(
        reset: Bool,
        liveMetrics: Bool = false,
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
