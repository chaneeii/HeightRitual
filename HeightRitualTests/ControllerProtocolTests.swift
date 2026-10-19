import XCTest
@testable import HeightRitual

/// The packet table and light bytes in SPEC section 6.
@MainActor
final class ControllerProtocolTests: XCTestCase {

    func testPackets() {
        XCTAssertEqual(ControlEvent.from(id: 1, value: 3), .knob(3))
        XCTAssertEqual(ControlEvent.from(id: 1, value: -2), .knob(-2))
        XCTAssertNil(ControlEvent.from(id: 1, value: 0))
        XCTAssertEqual(ControlEvent.from(id: 11, value: 1), .record)
        XCTAssertEqual(ControlEvent.from(id: 13, value: 1), .confirm)
        XCTAssertEqual(ControlEvent.from(id: 23, value: 1), .cancel)
        XCTAssertEqual(ControlEvent.from(id: 14, value: 1), .left)
        XCTAssertEqual(ControlEvent.from(id: 15, value: 1), .right)
        XCTAssertEqual(ControlEvent.from(id: 31, value: 0), .mode(.memory))
        XCTAssertEqual(ControlEvent.from(id: 31, value: 1), .mode(.make))
        XCTAssertEqual(ControlEvent.from(id: 32, value: 1), .autoPlayToggle)
        XCTAssertNil(ControlEvent.from(id: 12, value: 1), "Playback is no longer used")
        XCTAssertNil(ControlEvent.from(id: 21, value: 1), "Push is no longer used")
    }

    func testDebounce() {
        var debouncer = EventDebouncer()
        XCTAssertTrue(debouncer.accept(.confirm, at: 0))
        XCTAssertFalse(debouncer.accept(.confirm, at: 0.05), "identical within 100 ms")
        XCTAssertTrue(debouncer.accept(.confirm, at: 0.2))
        XCTAssertTrue(debouncer.accept(.left, at: 0.21), "a different event passes")
        XCTAssertTrue(debouncer.accept(.knob(1), at: 0.22))
        XCTAssertTrue(debouncer.accept(.knob(1), at: 0.23), "knob turns always pass")
    }

    func testControllerEventsGoThroughHandle() {
        let h = Harness()
        h.controller.onEvent?(.knob(1))
        XCTAssertEqual(h.state.highlight, 1)
    }

    func testLight() {
        let h = Harness()
        h.openFilm()
        XCTAssertEqual(h.controller.lights.last?.bytes, [0, 1], "off, make light")
        h.state.handle(.record)
        XCTAssertEqual(h.controller.lights.last?.recording, .steady, "steady while filming")
        h.state.handle(.record)
        XCTAssertEqual(h.controller.lights.last?.recording, .steady, "steady while cutting out")
        h.state.finishProcessing(ProcessedClip(estimatedMM: 1250))
        XCTAssertEqual(h.controller.lights.last?.recording, .off)
        h.state.handle(.confirm)
        XCTAssertEqual(h.controller.lights.last?.recording, .saved, "saved flash")
    }

    func testControllerPageListsPacketsAndStaysPut() {
        let h = Harness()
        h.state.openSettings()
        h.state.openSettingsPage(.controller)
        h.controller.onRaw?([14, 1])
        h.controller.onEvent?(.left)
        h.controller.onRaw?([23, 1])
        h.controller.onEvent?(.cancel)
        h.controller.onRaw?([31, 1])
        h.controller.onEvent?(.mode(.make))
        h.controller.onRaw?([99, 1])
        XCTAssertEqual(h.state.route, .settings(.controller), "controls only listed on the test page")
        XCTAssertEqual(h.state.controlLog.map(\.text),
                       ["[99, 1]  unknown control", "[31, 1]  Mode: Make", "[23, 1]  Cancel / Back", "[14, 1]  Left"])
        XCTAssertEqual(h.state.lastControl, .mode(.make))

        h.state.testLight(.steady)
        XCTAssertEqual(h.controller.lights.last?.recording, .steady)
        h.state.clearControlLog()
        XCTAssertTrue(h.state.controlLog.isEmpty)
    }
}
