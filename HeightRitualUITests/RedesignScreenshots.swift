import XCTest

/// Screenshots of the redesigned screens, phone and wall (through the debug wall preview), to
/// compare with Figma. Runs only with TEST_RUNNER_SCREENSHOT_DIR set.
final class RedesignScreenshots: XCTestCase {
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

    func testCaptureRedesign() {
        app.launch()
        if app.buttons["Set up later"].waitForExistence(timeout: 3) { app.buttons["Set up later"].tap() }
        pause(1.5)
        save("H-home-phone")

        debug(); save("H-home-wall")
        pad("Right"); pause(0.8); save("H-home-wall-right")
        pad("Left"); pause(0.5)
        pad("Confirm"); pause(0.15); save("H-home-wall-confirming")
        pause(0.8); save("H1-menu-wall")
        pad("Right"); pause(0.8); save("H1-menu-wall-lookback")
        pad("Back"); pause(0.8)
        debug()

        tap(201, 367); pause(1.2); save("H1-menu-phone")
        tap(45, 83); pause(1)

        tap(330, 358); pause(0.6)
        tap(330, 358); pause(0.8)
        tap(201, 367); pause(1.5); save("A2-add-phone")
        tap(201, 574); pause(0.3)
        tap(201, 574); pause(0.6); save("A2-add-phone-typed")
        debug(); save("A2-add-wall")
        debug()
    }

    // MARK: Helpers

    private func debug() {
        let button = app.buttons["Debug: show the wall"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
        pause(1)
    }

    private func pad(_ name: String) {
        app.buttons["Debug pad \(name)"].firstMatch.tap()
    }

    /// A tap at Figma phone coordinates (402 x 874), scaled to the screen.
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
