import XCTest

/// Moves around the app at random, many times, and checks the Make / Memory tab bar after every
/// step: shown and tappable on the first screen of each tab, covered on every screen pushed above.
/// Written after the tab bar stayed hidden on iOS 26 when moving back and forth.
final class NavigationStressTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // English labels whatever the simulator's language; start from the sample family.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestRoute"]
        app.launch()
        let later = app.buttons["Set up later"]
        if later.waitForExistence(timeout: 3) { later.tap() }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testRandomNavigationKeepsTheTabBarRight() {
        runRandom(pause: 0)
    }

    /// The same steps with a pause between them: tells a fast-input race from a fixed order.
    func testRandomNavigationSlowly() {
        runRandom(pause: 1, steps: 12)
    }

    private func runRandom(pause: TimeInterval, steps: Int = 60) {
        var random = SeededRandom(seed: 2026)
        for step in 1...steps {
            if pause > 0 { Thread.sleep(forTimeInterval: pause) }
            let action = Int.random(in: 0..<7, using: &random)
            print("STEP \(step) action \(action) route \(route) selected \(selectedTab) nav \(app.navigationBars.count)")
            switch action {
            case 0: tapTab("Make")
            case 1: tapTab("Memory")
            case 2: openMemberAndBack(random: &random)
            case 3: openRecordDetailAndBack()
            case 4: openSettingsAndClose()
            case 5: openFilmAndBack()
            default: openMemberAndBack(random: &random, depth: 2)
            }
            assertOnFirstScreen("after step \(step), action \(action)")
        }
    }

    /// The sequence the random run failed on (iOS 26): settings twice, then film.
    func testFilmAfterSettings() {
        tapTab("Make")
        openFilmAndBack()
        openSettingsAndClose()
        openFilmAndBack()
        openSettingsAndClose()
        openSettingsAndClose()
        openFilmAndBack()
        assertOnFirstScreen("end")
    }

    /// Steps 3 to 9 of the failing random run.
    func testFilmAfterVisitingMemory() {
        tapTab("Make")
        openFilmAndBack()
        tapTab("Memory")
        openFilmAndBack()          // switches back to Make itself
        openFilmAndBack()
        openSettingsAndClose()
        openSettingsAndClose()
        openFilmAndBack()
        assertOnFirstScreen("end")
    }

    /// Like the random run: Nora at step 6, then Leo.
    func testFilmLeoAfterNoraAndSettings() {
        tapTab("Make")
        openFilmAndBack()
        tapTab("Memory")
        openFilmAndBack()
        var always = SeededRandom(seed: 1)
        _ = always.next()
        openMember("Nora")
        openSettingsAndClose()
        openSettingsAndClose()
        openFilmAndBack()
        assertOnFirstScreen("end")
    }

    private func openMember(_ name: String) {
        guard let tile = visible(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name))) else {
            return XCTFail("no tile for \(name)")
        }
        tile.tap()
        assertTabBarCovered("inside \(name)")
        back()
    }

    /// The failing random run, step by step (seed 2026, steps 1 to 9).
    func testExactFailingOrder() {
        runSteps(skip: [])
    }

    /// The same order with one step left out; tells which step matters.
    func testExactOrderWithoutStep2() { runSteps(skip: [2]) }
    func testExactOrderWithoutStep4() { runSteps(skip: [4, 5]) }
    func testExactOrderWithoutStep6() { runSteps(skip: [6]) }
    func testExactOrderWithoutSettings() { runSteps(skip: [7, 8]) }

    private func runSteps(skip: Set<Int>) {
        let steps: [() -> Void] = [
            { self.tapTab("Make") },            // 1
            { self.tapTab("Make") },            // 2
            { self.openFilmAndBack() },         // 3
            { self.tapTab("Memory") },          // 4
            { self.openFilmAndBack() },         // 5
            { self.openMember("Nora") },        // 6
            { self.openSettingsAndClose() },    // 7
            { self.openSettingsAndClose() },    // 8
            { self.openFilmAndBack() },         // 9
        ]
        for (index, step) in steps.enumerated() where !skip.contains(index + 1) {
            step()
            assertOnFirstScreen("after step \(index + 1)")
        }
    }

    /// Tapping the tab that is already selected, then filming.
    func testFilmAfterRetappingTheSelectedTab() {
        tapTab("Make")
        tapTab("Make")
        openFilmAndBack()
        openFilmAndBack()
        assertOnFirstScreen("end")
    }

    /// Only the tab switch, without Settings.
    func testFilmAfterTabSwitch() {
        tapTab("Make")
        openFilmAndBack()
        tapTab("Memory")
        openFilmAndBack()
        openFilmAndBack()
        openFilmAndBack()
        assertOnFirstScreen("end")
    }

    /// Same without Settings, to tell the two apart.
    func testFilmRepeatedly() {
        for _ in 1...4 { openFilmAndBack() }
        assertOnFirstScreen("end")
    }

    // MARK: Steps

    private func tapTab(_ name: String) {
        app.tabBars.buttons[name].tap()
    }

    /// Opens Nora or Leo in the current tab, checks the tab bar is covered, goes back.
    private func openMemberAndBack(random: inout SeededRandom, depth: Int = 1) {
        let name = Bool.random(using: &random) ? "Nora" : "Leo"
        guard let tile = visible(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name))) else {
            return XCTFail("no tile for \(name)")
        }
        tile.tap()
        assertTabBarCovered("inside \(name)")
        for _ in 1..<depth {
            // Memory: one more level, the record detail.
            if let card = visible(app.buttons.matching(NSPredicate(format: "label CONTAINS ' of '"))) {
                card.tap()
                assertTabBarCovered("record detail")
                back()
            }
        }
        back()
    }

    private func openRecordDetailAndBack() {
        tapTab("Memory")
        guard let tile = visible(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Nora'"))) else {
            return XCTFail("no Nora")
        }
        tile.tap()
        guard let card = visible(app.buttons.matching(NSPredicate(format: "label CONTAINS ' of '"))) else {
            return XCTFail("no record card")
        }
        card.tap()
        assertTabBarCovered("record detail")
        back()
        assertTabBarCovered("memory wall")
        back()
    }

    private func openSettingsAndClose() {
        app.buttons["Settings"].firstMatch.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
    }

    private func openFilmAndBack() {
        tapTab("Make")
        guard let tile = visible(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Leo'"))) else {
            return XCTFail("no Leo")
        }
        tile.tap()
        if visible(app.buttons.matching(NSPredicate(format: "label == 'Record'"))) == nil {
            print("TREE-START\n" + app.debugDescription + "\nTREE-END")
            XCTFail("film screen not shown; route: \(route)")
        }
        assertTabBarCovered("film")
        back()
    }

    /// The TabView keeps both tabs' grids alive; only the one on screen can be tapped.
    private func visible(_ query: XCUIElementQuery, timeout: TimeInterval = 3) -> XCUIElement? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if let element = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < end
        return nil
    }

    private func back() {
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 3))
        bar.buttons.element(boundBy: 0).tap()
        // Let the pop animation finish, as a person would: a push sent during it is refused by
        // UIKit (machine-speed taps only).
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: Checks

    private var selectedTab: String {
        app.tabBars.buttons.allElementsBoundByIndex.filter { $0.isSelected }.map(\.label).joined()
    }

    private var route: String {
        let label = app.staticTexts["route-debug"]
        return label.exists ? label.label : "?"
    }

    private func assertOnFirstScreen(_ context: String) {
        let tabBar = app.tabBars.firstMatch
        let shown = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: shown, object: tabBar)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 3), .completed,
                       "tab bar missing on the first screen, \(context); route: \(route)")
    }

    private func assertTabBarCovered(_ context: String) {
        let tabBar = app.tabBars.firstMatch
        let covered = NSPredicate(format: "exists == false OR hittable == false")
        let expectation = XCTNSPredicateExpectation(predicate: covered, object: tabBar)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 3), .completed,
                       "tab bar still showing on a pushed screen: \(context); route: \(route)")
    }
}

/// Same sequence of steps on every run, so a failure can be repeated.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
