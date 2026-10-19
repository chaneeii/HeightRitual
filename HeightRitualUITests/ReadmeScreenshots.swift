import XCTest

/// Saves the README screenshots (docs/images). Not part of the normal test run; start it with
/// TEST_RUNNER_SCREENSHOT_DIR set to the folder to write into.
final class ReadmeScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL?

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
            throw XCTSkip("SCREENSHOT_DIR not set")
        }
        folder = URL(fileURLWithPath: path)
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    /// Run on a fresh install so the welcome pages and the setup wizard show.
    func testCaptureScreens() {
        app.launch()
        if app.buttons["Set up later"].waitForExistence(timeout: 4) {
            save("W0-1-welcome")
            app.buttons["Next"].tap(); pause(); save("W0-2-welcome-make")
            app.buttons["Next"].tap(); pause(); save("W0-3-welcome-memory")
            app.buttons["Set up the wall"].tap(); pause(); save("W1-setup-permissions")
            app.buttons["Next"].tap(); pause(); save("W2-setup-fit-to-wall")
            app.buttons["Next"].tap(); pause(1.5); save("W3-setup-camera-position")
            app.buttons["Finish"].tap(); pause()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))

        app.tabBars.buttons["Memory"].tap(); pause(); save("R1-memory-choose")
        app.tabBars.buttons["Make"].tap(); pause(); save("M1-make-choose")

        tapFirst("label CONTAINS 'Leo'"); pause(1.5); save("M2-film")
        back()

        tapFirst("label == 'Add a family member'"); pause(); save("A1-member-new")
        app.buttons["Cancel"].firstMatch.tap(); pause()

        app.tabBars.buttons["Memory"].tap()
        tapFirst("label CONTAINS 'Nora'"); pause(2); save("R2-memory-wall-auto")
        if let manual = visible(app.buttons.matching(NSPredicate(format: "label == 'Manual'"))) {
            manual.tap(); pause(1.5); save("R2-memory-wall-manual")
        }
        tapFirst("label == 'Show the wall full screen'"); pause(1.5); save("R2F-wall-full-screen")
        tapFirst("label == 'Close'"); pause()
        tapFirst("label CONTAINS ' of '"); pause(1.5); save("R3-record-detail")
        back(); back()

        app.buttons["Settings"].firstMatch.tap(); pause(); save("S-settings")
        tapFirst("label BEGINSWITH 'Family'"); pause(); save("S-family")
        tapFirst("label CONTAINS 'Nora'"); pause(); save("A1-member-edit")
    }

    /// One settings page per launch, so no back navigation inside the sheet is needed.
    func testCaptureSettingsPages() {
        for (label, name, scroll) in [("Setup guide", "S-setup-guide", false), ("Controller", "S6-controller", true),
                                      ("Permissions", "S5-permissions", true)] {
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
            app.buttons["Settings"].firstMatch.tap(); pause()
            if scroll { app.swipeUp(); pause() }
            tapFirst("label BEGINSWITH '\(label)'"); pause(1.5); save(name)
            app.terminate()
        }
    }

    private func back() {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        pause()
    }

    private func visible(_ query: XCUIElementQuery) -> XCUIElement? {
        query.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
    }

    private func tapFirst(_ format: String) {
        var element: XCUIElement?
        for _ in 0..<15 where element == nil {
            element = visible(app.buttons.matching(NSPredicate(format: format)))
                ?? visible(app.cells.matching(NSPredicate(format: format)))
            if element == nil { pause(0.2) }
        }
        XCTAssertNotNil(element, format)
        element?.tap()
    }

    private func pause(_ seconds: TimeInterval = 0.8) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func save(_ name: String) {
        guard let folder else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
