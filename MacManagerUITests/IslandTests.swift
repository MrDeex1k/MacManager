import AppKit
import XCTest

final class IslandTests: AppUITestSupport {
    @MainActor
    func testReservedRegionPrototypeInRealIslandPanel() throws {
        #if MM_RESERVED_REGION_PROBE
        try checkReservedRegionPrototype(ignoresSafeArea: false)
        try checkReservedRegionPrototype(ignoresSafeArea: true)
        #else
        throw XCTSkip("Build with MM_RESERVED_REGION_PROBE and the macOS 27.1+ SDK to run this prototype")
        #endif
    }

    #if MM_RESERVED_REGION_PROBE
    @MainActor
    private func checkReservedRegionPrototype(ignoresSafeArea: Bool) throws {
        guard #available(macOS 27.1, *) else { throw XCTSkip("ReservedRegion requires macOS 27.1") }
        let app = launch(reset: true, islandReservedRegionProbe: true, islandProbeIgnoresSafeArea: ignoresSafeArea)
        defer { app.terminate() }
        element("navigation.island", in: app).click()
        let report = element("island.debug.reservedRegions", in: app)
        func command(_ title: String) {
            app.menuBars.menuBarItems["View"].click(); app.menuItems[title].click()
        }
        func observation(section: String, height: CGFloat?, name: String) throws -> [String: Any] {
            func json() -> [String: Any]? {
                for text in [report.value as? String, report.label].compactMap({ $0 }) {
                    if let data = text.data(using: .utf8),
                       let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return value }
                }
                return nil
            }
            let ready = NSPredicate { _, _ in
                guard let value = json(), value["section"] as? String == section,
                      let sample = value["sample"] as? [String: Any], let size = sample["size"] as? [Double] else { return false }
                let targetHeight = height ?? CGFloat((value["legacyTopInset"] as? Double ?? 0) + 306)
                return size.count == 2 && size[0] > 0 && abs(size[1] - targetHeight) < 1 &&
                    abs(self.element("island.panel", in: app).frame.height - targetHeight) < 1
            }
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 5)
            if result != .completed { print("ReservedRegion probe pending: \(report.label); value=\(String(describing: report.value))") }
            XCTAssertEqual(result, .completed)
            let value = try XCTUnwrap(json())
            let sample = try XCTUnwrap(value["sample"] as? [String: Any])
            XCTAssertEqual(sample["ignoresSafeArea"] as? Bool, ignoresSafeArea)
            let size = try XCTUnwrap(sample["size"] as? [Double])
            let frameInRoot = try XCTUnwrap(sample["frameInRoot"] as? [[Double]])
            let origin = try XCTUnwrap(frameInRoot.first)
            XCTAssertEqual(origin[0], 0, accuracy: 1)
            XCTAssertEqual(origin[1], 0, accuracy: 1, "The probe must cover the camera strip, not start below its safe area")
            let regions = try XCTUnwrap(sample["regions"] as? [[String: Any]])
            XCTAssertNotNil(value["cameraComparison"] as? String)
            XCTAssertEqual(sample["activeOcclusions"] as? Int,
                regions.filter { $0["kind"] as? String == "occlusion" && $0["active"] as? Bool == true }.count)
            XCTAssertEqual(sample["activeDivisions"] as? Int,
                regions.filter { $0["kind"] as? String == "division" && $0["active"] as? Bool == true }.count)
            let text = String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!
            print("ReservedRegion observation [\(name)]: \(text)")
            let attachment = XCTAttachment(string: text); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(element("island.panel", in: app).frame.height, size[1], accuracy: 1)
            XCTAssertEqual(element("island.panel", in: app).frame.width, size[0], accuracy: 1)
            return value
        }

        command("Open Island")
        XCTAssertTrue(app.textFields["island.search"].waitForExistence(timeout: 5))
        let clipboard = try observation(section: "clipboard", height: expectedClipboardIslandHeight, name: "Built-in clipboard")
        app.buttons["island.section.music"].click()
        _ = try observation(section: "music", height: 250, name: "Built-in music")
        app.buttons["island.section.clipboard"].click()
        _ = try observation(section: "clipboard", height: expectedClipboardIslandHeight, name: "Built-in clipboard return")
        app.buttons["island.close"].click()
        XCTAssertTrue(element("island.panel", in: app).waitForNonExistence(timeout: 3))

        let external = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) == 0
        }
        if let external {
            command("Probe Island on External Display"); command("Open Island")
            // visibleFrame can differ between the runner and the app when its menu bar
            // becomes visible on the external display. Use the app's recorded inset.
            let value = try observation(section: "clipboard", height: nil, name: "External clipboard")
            XCTAssertEqual(value["builtIn"] as? Bool, false)
            XCTAssertNil(value["legacyCameraFrame"])
            let desktopTop = try XCTUnwrap(NSScreen.screens.first).frame.maxY
            XCTAssertEqual(element("island.panel", in: app).frame.minY, desktopTop - external.frame.maxY, accuracy: 1)
            app.buttons["island.close"].click()
            command("Probe Island on Built-in Display"); command("Open Island")
            let restored = try observation(section: "clipboard", height: expectedClipboardIslandHeight, name: "Built-in restored")
            XCTAssertEqual(restored["cameraComparison"] as? String, clipboard["cameraComparison"] as? String)
            app.buttons["island.close"].click()
        }
    }
    #endif

    @MainActor
    func testIslandSectionPreferencesAndAutomaticRestore() throws {
        let app = launch(reset: true)
        defer { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
        XCTAssertFalse(app.checkBoxes["island.enabled"].exists)
        element("navigation.island", in: app).click()
        XCTAssertTrue(element("settings.island.content", in: app).waitForExistence(timeout: 3))
        for name in ["clipboard", "music", "podcast"] {
            let toggle = app.checkBoxes["island.enabled." + name]
            XCTAssertTrue(toggle.waitForExistence(timeout: 3))
            revealIslandToggle(toggle, in: app)
            toggle.click()
            XCTAssertEqual(switchValue(toggle), 0)
        }
        app.menuBars.menuBarItems["View"].click(); app.menuItems["Open Island"].click()
        XCTAssertTrue(app.buttons["island.section.spotify"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("spotify.deferred", in: app).waitForExistence(timeout: 3))
        for name in ["clipboard", "music", "podcast"] {
            XCTAssertFalse(app.buttons["island.section." + name].exists)
        }
        app.buttons["island.close"].click()
        element("navigation.island", in: app).click()
        let spotify = app.checkBoxes["island.enabled.spotify"]
        revealIslandToggle(spotify, in: app)
        XCTAssertTrue(spotify.isHittable)
        XCTAssertEqual(switchValue(spotify), 1)
        spotify.click()
        XCTAssertEqual(switchValue(spotify), 0)
        XCTAssertEqual(switchValue(app.checkBoxes["island.enabled"]), 0)
        app.menuBars.menuBarItems["View"].click()
        XCTAssertFalse(app.menuItems["Open Island"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        let master = app.checkBoxes["island.enabled"]
        revealIslandToggle(master, in: app); master.click()
        for name in ["clipboard", "music", "podcast", "spotify"] {
            XCTAssertEqual(switchValue(app.checkBoxes["island.enabled." + name]), 1)
        }
        app.menuBars.menuBarItems["View"].click(); app.menuItems["Open Island"].click()
        for name in ["clipboard", "music", "podcast", "spotify"] {
            XCTAssertTrue(app.buttons["island.section." + name].waitForExistence(timeout: 3))
        }
        app.buttons["island.close"].click()
    }

    @MainActor
    func testFourIslandSectionsAndPodcastControls() throws {
        let app = launch(reset: true, clipboardFixture: true)
        defer { app.terminate() }
        element("navigation.island", in: app).click()
        let podcastWork = element("island.debug.podcasts", in: app)
        app.menuBars.menuBarItems["View"].click(); app.menuItems["Open Island"].click()
        let identifiers = ["clipboard", "music", "podcast", "spotify"]
        for name in identifiers {
            let button = app.buttons["island.section." + name]
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThan(button.frame.width, 70)
            XCTAssertFalse(button.label.isEmpty)
        }
        app.typeKey("3", modifierFlags: .option)
        XCTAssertTrue(app.staticTexts["Test episode"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["island.section.podcast"].isSelected)
        app.buttons["podcast.play"].click()
        XCTAssertTrue(app.buttons["podcast.pause"].waitForExistence(timeout: 3))
        app.buttons["podcast.next"].click()
        XCTAssertTrue(app.staticTexts["2:30"].waitForExistence(timeout: 3))
        app.buttons["podcast.previous"].click()
        XCTAssertTrue(app.staticTexts["2:15"].waitForExistence(timeout: 3))
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.buttons["podcast.play"].waitForExistence(timeout: 3))
        let proof = XCTAttachment(screenshot: element("island.panel", in: app).screenshot())
        proof.name = "Four sections and Podcasts player"; proof.lifetime = .keepAlways; add(proof)
        app.typeKey("4", modifierFlags: .option)
        XCTAssertTrue(element("spotify.deferred", in: app).waitForExistence(timeout: 3))
        let idle = NSPredicate(format: "label == %@ OR value == %@", "visible=0;work=0;artwork=0", "visible=0;work=0;artwork=0")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: idle, object: podcastWork)], timeout: 3), .completed)
        app.typeKey("2", modifierFlags: .option)
        XCTAssertTrue(app.staticTexts["Test song 1"].waitForExistence(timeout: 3))
        app.typeKey("1", modifierFlags: .option)
        XCTAssertTrue(app.textFields["island.search"].waitForExistence(timeout: 3))
        app.buttons["island.close"].click()
    }

    @MainActor
    func testPodcastPermissionAndUnavailableWindowStates() throws {
        let app = launch(reset: true, podcastAccessRequired: true)
        defer { app.terminate() }
        app.menuBars.menuBarItems["View"].click(); app.menuItems["Open Island"].click()
        app.buttons["island.section.podcast"].click()
        XCTAssertTrue(app.buttons["podcast.connect"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["podcast.play"].isEnabled)
        app.buttons["podcast.connect"].click() // Fixture, never changes real TCC.
        XCTAssertTrue(app.staticTexts["Test episode"].waitForExistence(timeout: 3))
        app.terminate()
        app.launchArguments.append("--podcast-window-required")
        app.launchArguments.removeAll { $0 == "--podcast-access-required" }
        app.launch(); app.activate()
        app.menuBars.menuBarItems["View"].click(); app.menuItems["Open Island"].click()
        app.buttons["island.section.podcast"].click()
        XCTAssertTrue(app.staticTexts["podcast.status"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["podcast.open"].isHittable)
        XCTAssertFalse(app.buttons["podcast.play"].isEnabled)
    }

    @MainActor
    func testIslandSessionSuspensionStopsPlayersAndAllowsReopen() throws {
        let app = launch(reset: true)
        defer { app.terminate() }
        element("navigation.island", in: app).click()
        let podcastWork = element("island.debug.podcasts", in: app)
        app.menuBars.menuBarItems["View"].click(); app.menuItems["Open Island"].click()
        app.buttons["island.section.podcast"].click()
        XCTAssertTrue(app.staticTexts["Test episode"].waitForExistence(timeout: 3))
        app.menuBars.menuBarItems["View"].click(); app.menuItems["Suspend Island Session"].click()
        XCTAssertTrue(element("island.panel", in: app).waitForNonExistence(timeout: 3))
        let idle = NSPredicate(format: "label == %@ OR value == %@", "visible=0;work=0;artwork=0", "visible=0;work=0;artwork=0")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: idle, object: podcastWork)], timeout: 3), .completed)
        app.menuBars.menuBarItems["View"].click(); app.menuItems["Open Island"].click()
        XCTAssertFalse(element("island.panel", in: app).exists)
        app.menuBars.menuBarItems["View"].click(); app.menuItems["Resume Island Session"].click()
        app.menuBars.menuBarItems["View"].click(); app.menuItems["Open Island"].click()
        XCTAssertTrue(app.staticTexts["Test episode"].waitForExistence(timeout: 3))
        app.buttons["island.close"].click()
    }

    @MainActor
    func testIslandGlassSectionResizeAndClose() throws {
        let app = launch(reset: true, clipboardFixture: true, islandClipboardFixture: true, islandDenseClipboardFixture: true)
        defer { app.terminate() }
        element("navigation.island", in: app).click()
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
        XCTAssertEqual(panel.frame.height, inset + 306, accuracy: 1, "Hover must not expand the panel to screen height")
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
        XCTAssertEqual(panel.frame.height, inset + 306, accuracy: 1)
        outside.hover()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        activation.hover()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(panel.frame.height, inset + 306, accuracy: 1, "Reopening must retain the bounded height")
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
        // The footer includes the extra 2 pt requested above its controls.
        XCTAssertLessThanOrEqual(capture.frame.minY - firstCard.frame.maxY, 26, "Footer should sit directly below the shelf with scrollbar clearance")
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

}
