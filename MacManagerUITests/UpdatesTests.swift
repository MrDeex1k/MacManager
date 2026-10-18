import AppKit
import XCTest

final class UpdatesTests: AppUITestSupport {
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
        scrollTo(automatic, in: app)
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

}
