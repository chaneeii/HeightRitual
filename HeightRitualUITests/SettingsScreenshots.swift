import XCTest

/// Every Settings page on the phone and on the wall (through the debug wall preview), for the
/// Figma redraw. Runs only with TEST_RUNNER_SCREENSHOT_DIR set.
final class SettingsScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL?

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
            throw XCTSkip("SCREENSHOT_DIR not set")
        }
        folder = URL(fileURLWithPath: path)
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    /// The projector grid and each page it opens, one tile at a time.
    func testWallSettings() {
        launch()
        debug()
        pad("Back"); pause(1.2); save("W00-grid")
        let names = ["setup-guide", "family", "fit-to-wall", "camera-position", "units",
                     "sound", "controller", "permissions", "sample-family", "delete-everything"]
        for (index, name) in names.enumerated() {
            if index > 0 { pad("Right"); pause(0.4) }
            if index == 1 { save("W00-grid-family-highlighted") }
            pad("Confirm"); pause(1.2); save(String(format: "W%02d-%@", index + 1, name))
            pad("Back"); pause(0.3)
            if name == "controller" { pad("Back"); pause(0.3) }
            pause(0.8)
        }
    }

    /// A member from Family on the wall: its rows, the colours, the letter wheel and the question.
    func testWallMember() {
        launch()
        debug()
        pad("Back"); pause(1.2)
        pad("Right"); pause(0.3)
        pad("Confirm"); pause(0.8)
        pad("Confirm"); pause(1.2); save("WM1-member")
        pad("Right"); pause(0.3)
        pad("Confirm"); pause(1.2); save("WM2-rename")
        pad("Back"); pause(0.5)
        pad("Right"); pause(0.3)
        pad("Confirm"); pause(1.2); save("WM3-colour")
        pad("Back"); pause(0.5)
        pad("Right"); pause(0.3)
        pad("Confirm"); pause(1.2); save("WM4-delete")
        pad("Back"); pause(0.5)
    }

    /// The phone's member page from Settings > Family.
    func testPhoneMember() {
        launch()
        app.buttons["Settings"].firstMatch.tap(); pause(1.2)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Family'")).firstMatch.tap(); pause(1.2)
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Nora'")).firstMatch.tap(); pause(1.5)
        save("PM1-member")
    }

    /// The phone's Settings list and each page it opens.
    func testPhoneSettings() {
        let rows = ["Family", "Setup guide", "Fit to wall", "Camera position", "Units",
                    "Sound", "Controller", "Permissions"]
        for (index, row) in rows.enumerated() {
            launch()
            app.buttons["Settings"].firstMatch.tap(); pause(1.2)
            if index == 0 {
                save("P00-list-top")
                app.swipeUp(); pause(0.8); save("P00-list-bottom")
                app.swipeDown(); pause(0.8)
            }
            if index >= 4 { app.swipeUp(); pause(0.8) }
            let cell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)).firstMatch
            if cell.waitForExistence(timeout: 2) { cell.tap(); pause(1.5) }
            save(String(format: "P%02d-%@", index + 1, row.lowercased().replacingOccurrences(of: " ", with: "-")))
            app.terminate()
        }
    }

    private func launch() {
        app.launch()
        if app.buttons["Set up later"].waitForExistence(timeout: 3) { app.buttons["Set up later"].tap() }
        pause(1.2)
    }

    private func debug() {
        let button = app.buttons["Debug: show the wall"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
        pause(1)
    }

    private func pad(_ name: String) { app.buttons["Debug pad \(name)"].firstMatch.tap() }
    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func save(_ name: String) {
        guard let folder else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
