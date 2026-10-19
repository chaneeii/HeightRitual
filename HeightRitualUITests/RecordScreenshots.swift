import XCTest

/// Screenshots of Record and Lookback, phone and wall. Runs only with TEST_RUNNER_SCREENSHOT_DIR set.
final class RecordScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL?

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
            throw XCTSkip("SCREENSHOT_DIR not set")
        }
        folder = URL(fileURLWithPath: path)
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-DebugFakeClip"]
    }

    func testCaptureRecordAndLookback() {
        app.launch()
        if app.buttons["Set up later"].waitForExistence(timeout: 3) { app.buttons["Set up later"].tap() }
        pause(1.5)
        tap(201, 367); pause(1)            // Nora -> menu
        tap(124, 414); pause(1.5)          // Record
        save("M2-film-phone")
        debug(); save("M2-film-wall")
        pad("Confirm"); pause(2.2); save("M2-filming-wall")
        debug(); save("M2-filming-phone")
        pause(4); save("M3-height-phone")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.76))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.76)))
        pause(1); save("M3-height-phone-dragged")
        debug(); save("M3-height-wall")
        pad("Right"); pause(0.8); save("M3-height-wall-right")
        pad("Confirm"); pause(1.5); save("M4-saved-wall")
        debug(); save("M4-saved-phone")
        tap(201, 738); pause(2); save("R2-lookback-phone")
        debug(); save("R2-lookback-wall")
        pad("Left"); pause(1.2); save("R2-lookback-wall-moved")
        debug()
    }

    private func debug() {
        let button = app.buttons["Debug: show the wall"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
        pause(1)
    }

    private func pad(_ name: String) { app.buttons["Debug pad \(name)"].firstMatch.tap() }

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
