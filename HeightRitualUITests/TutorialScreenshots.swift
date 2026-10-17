import XCTest

/// Screenshots of the onboarding with the controller. Runs only with TEST_RUNNER_SCREENSHOT_DIR set.
final class TutorialScreenshots: XCTestCase {
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

    func testCaptureTutorial() {
        app.launch()
        pause(1.5)
        app.buttons["Settings"].firstMatch.tap(); pause(1)
        app.swipeUp(); pause(0.5)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Onboarding with controller'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap(); pause(1.5)
        save("T01-welcome")
        press("confirm"); pause(1); save("T02-family")
        press("confirm"); pause(1); save("T03-name")
        press("confirm"); for _ in 0..<13 { press("right", wait: 0.05) }; press("confirm")
        for _ in 0..<13 { press("left", wait: 0.05) }; press("confirm"); pause(0.6); save("T03-name-typed")
        press("left"); press("confirm"); pause(1.2); save("T04-choose-record")
        press("confirm"); pause(1.2); save("T05-film")
        press("confirm"); pause(2); save("T05-filming")
        pause(4); save("T06-height")
        for _ in 0..<4 { press("right", wait: 0.15) }
        tap(296, 652); pause(0.8); save("T06-height-set")
        press("confirm"); pause(1.5); save("T07-saved")
        press("back"); pause(1.2); save("T08-choose-lookback")
        press("right"); pause(0.8); save("T08-choose-lookback-selected")
        press("confirm"); pause(1.5); save("T09-lookback")
        debug(); save("T09-lookback-wall")
        debug()
        press("confirm"); pause(1.5); save("T10-ready")
        press("begin"); pause(1.5); save("T11-home")
    }

    /// The debug button on top: in the wall preview there are two, the preview's is the last.
    private func debug() {
        app.buttons.matching(NSPredicate(format: "label == 'Debug: show the wall'")).allElementsBoundByIndex
            .last(where: { $0.isHittable })?.tap()
        pause(1.2)
    }

    private func press(_ name: String, wait: TimeInterval = 0.3) {
        if name == "begin" {
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'to begin'")).firstMatch.tap()
        } else {
            app.buttons[name].firstMatch.tap()
        }
        pause(wait)
    }

    private func tap(_ x: CGFloat, _ y: CGFloat) {
        let frame = app.windows.firstMatch.frame
        let scale = min(frame.width / 402, frame.height / 874)
        let dx = (frame.width - 402 * scale) / 2 + x * scale
        let dy = (frame.height - 874 * scale) / 2 + y * scale
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: dx, dy: dy)).tap()
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func save(_ name: String) {
        guard let folder else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
