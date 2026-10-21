import AppKit
import XCTest

final class ClipboardTests: AppUITestSupport {
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
    func testClipboardDefaultsEnabledAndLocalizes() throws {
        let app = launch(reset: true)
        defer { app.terminate() }
        element("navigation.clipboard", in: app).click()
        XCTAssertTrue(app.buttons["clipboard.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["clipboard.pause"].label, "Pause")
        XCTAssertFalse(app.buttons["clipboard.enable"].exists)
        let englishStates = ["Clipboard access required", "Clipboard access denied", "Saving new copies"]
        let status = app.staticTexts["clipboard.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label IN %@ OR value IN %@", englishStates, englishStates), object: status
        )], timeout: 5), .completed)
        element("navigation.settings", in: app).click()
        app.popUpButtons["settings.language"].click()
        app.menuItems["Polski"].click()
        element("navigation.clipboard", in: app).click()
        XCTAssertTrue(app.buttons["clipboard.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["clipboard.pause"].label, "Wstrzymaj")
        XCTAssertFalse(app.buttons["clipboard.enable"].exists)
        let polishStates = ["Wymagany dostęp do schowka", "Brak zgody na dostęp do schowka", "Zapisywanie nowych kopii"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label IN %@ OR value IN %@", polishStates, polishStates), object: status
        )], timeout: 5), .completed)
    }

    @MainActor
    func testDetailsKeepWriteFailureAndRetrySuccessfully() throws {
        let app = launch(reset: true, clipboardFixture: true, clipboardWriteFailure: true)
        defer { app.terminate() }
        element("navigation.clipboard", in: app).click()
        let detail = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "clipboard.detail.")).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        detail.click()
        app.buttons["clipboard.detail.restore"].click()
        XCTAssertTrue(element("clipboard.detail.error", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["clipboard.detail.restore"].isEnabled)
        try performAccessibilityAudit(in: app, for: [.action, .sufficientElementDescription, .parentChild])
        app.buttons["clipboard.detail.restore"].click()
        XCTAssertTrue(app.buttons["clipboard.detail.restore"].waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testClipboardAndPanelsAccessibility() throws {
        let app = launch(reset: true, clipboardFixture: true)
        defer { app.terminate() }
        let types: XCUIAccessibilityAuditType = [.action, .sufficientElementDescription, .parentChild, .contrast]
        element("navigation.clipboard", in: app).click()
        let detail = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "clipboard.detail.")).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app, for: types)
        detail.click()
        XCTAssertTrue(app.buttons["clipboard.detail.restore"].waitForExistence(timeout: 3))
        try performAccessibilityAudit(in: app, for: types)
        app.buttons["clipboard.detail.restore"].click()
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Open launcher"].click()
        XCTAssertTrue(app.textFields["launcher.search"].waitForExistence(timeout: 3))
        app.textFields["launcher.search"].typeKey(.tab, modifierFlags: [])
        let launcherCopy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "launcher.result.clipboard:")).firstMatch
        XCTAssertTrue(launcherCopy.waitForExistence(timeout: 3))
        try performAccessibilityAudit(in: app, for: types)
        app.textFields["launcher.search"].typeKey(.escape, modifierFlags: [])
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Open Island"].click()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "island.clipboard.restore.")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        try performAccessibilityAudit(in: app, for: types)
        card.click()
        let copied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Copied"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [copied], timeout: 3), .completed)
        try performAccessibilityAudit(in: app, for: types)
        app.buttons["island.close"].click()
    }

}
