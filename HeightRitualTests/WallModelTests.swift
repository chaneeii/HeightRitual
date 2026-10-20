import XCTest
@testable import HeightRitual

/// What the wall shows per screen (SPEC 5, wall column).
@MainActor
final class WallModelTests: XCTestCase {

    func testSettingsShowTiles() {
        let h = Harness()
        h.state.openSettings()
        XCTAssertEqual(h.state.wallModel.kind, .settingsMenu)
        h.state.openSettingsPage(.family)
        XCTAssertEqual(h.state.wallModel.kind, .settingsFamily, "every settings page has its own wall")
    }

    func testHomeShowsTheScreenItself() {
        let h = Harness()
        XCTAssertEqual(h.state.wallModel.kind, .screen)
        h.confirm()
        XCTAssertEqual(h.state.wallModel.kind, .screen, "the member menu too")
    }

    func testMemoryWallMarksFigureAndCaption() {
        let h = Harness()
        h.openMemoryWall()
        var wall = h.state.wallModel
        XCTAssertEqual(wall.kind, .marks)
        XCTAssertEqual(wall.marks.count, 6, "a mark for every record")
        XCTAssertEqual(wall.marks.filter(\.selected).map(\.heightMM), [1210])
        XCTAssertEqual(wall.figure?.heightMM, 1210)
        XCTAssertNil(wall.figure?.posterFile, "sample records are soft outlines")
        XCTAssertEqual(wall.caption, "Nora, Aug 2025, 121.0 cm")

        h.state.handle(.knob(-5))
        wall = h.state.wallModel
        XCTAssertEqual(wall.figure?.heightMM, 870)
        XCTAssertEqual(wall.caption, "Nora, Aug 2020, 87.0 cm")

        h.state.settings.unit = .ftin
        XCTAssertEqual(h.state.wallModel.caption, "Nora, Aug 2020, 2 ft 10 1/4 in", "the wall follows the unit")
    }

    func testMemoryWallWithoutRecords() {
        let h = Harness()
        h.state.store.addMember(name: "Ada")
        h.state.handle(.knob(2))
        h.confirm()
        h.state.handle(.right)
        h.confirm()
        XCTAssertEqual(h.state.route, .memoryWall)
        XCTAssertEqual(h.state.wallModel.headline, "No records yet")
        XCTAssertNil(h.state.wallModel.figure)
        h.state.handle(.autoPlayToggle)
        XCTAssertFalse(h.state.isAutoPlaying, "nothing to play")
    }

    func testFilmGuideAndDarkCountdown() {
        let h = Harness()
        h.openFilm()
        var wall = h.state.wallModel
        XCTAssertEqual(wall.kind, .footGuide)
        XCTAssertEqual(wall.guideMM, 1310, "last height plus 10 cm")
        h.state.handle(.record)
        XCTAssertEqual(h.state.wallModel.kind, .footGuide, "the outline stays while filming")
    }

    func testHeightAndSavedShowTheScreen() {
        let h = Harness()
        h.openHeight(estimateMM: 1250)
        XCTAssertEqual(h.state.wallModel.kind, .screen)
        h.state.handle(.confirm)
        XCTAssertEqual(h.state.route, .makeSaved)
        XCTAssertEqual(h.state.wallModel.kind, .screen)
    }

    func testFitToWallShowsRuler() {
        let h = Harness()
        h.state.openSettings()
        h.state.openSettingsPage(.fitToWall)
        XCTAssertEqual(h.state.wallModel.kind, .ruler)
        XCTAssertEqual(h.state.wallModel.fitValue, .floor)
    }
}
