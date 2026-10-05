import XCTest
@testable import HeightRitual

/// SPEC 8: the foot guide from the camera position values.
@MainActor
final class FootGuideTests: XCTestCase {

    func testGuideFromCameraPosition() {
        let camera = CameraPosition(floorY: 0.9, y100: 0.5, centerX: 0.48)
        let guide = FootGuide.make(camera: camera, outlineMM: 1310)
        XCTAssertTrue(guide.isCalibrated)
        XCTAssertEqual(guide.floorY, 0.9)
        XCTAssertEqual(guide.centerX, 0.48)
        XCTAssertEqual(guide.cmY, 0.004, accuracy: 1e-12)
        // 131 cm above the floor line: 0.9 - 131 * 0.004
        XCTAssertEqual(guide.topY, 0.376, accuracy: 1e-9)
    }

    func testFallbackWithoutCameraPosition() {
        let guide = FootGuide.make(camera: nil, outlineMM: 1200)
        XCTAssertFalse(guide.isCalibrated)
        XCTAssertEqual(guide.centerX, 0.5)
        XCTAssertLessThan(guide.topY, guide.floorY)
    }

    func testOutlineHeight() {
        XCTAssertEqual(FootGuide.outlineMM(lastMM: 1210), 1310, "last height plus 10 cm")
        XCTAssertEqual(FootGuide.outlineMM(lastMM: nil), 1200, "first record: 120 cm")
    }

    func testFilmScreenUsesSavedPosition() {
        let h = Harness()
        h.state.saveCameraPosition(CameraPosition(floorY: 0.88, y100: 0.48))
        h.openFilm()
        XCTAssertEqual(h.state.footGuide.floorY, 0.88)
        XCTAssertEqual(h.state.footGuide.topY, 0.88 - 131 * 0.004, accuracy: 1e-9)
    }

    func testCameraRunsOnFilmAndCameraPositionOnly() {
        let h = Harness()
        h.openFilm()
        XCTAssertTrue(h.camera.previewing)
        h.state.openSettings()
        XCTAssertFalse(h.camera.previewing)
        h.state.openSettingsPage(.cameraPosition)
        XCTAssertTrue(h.camera.previewing)
        h.state.handle(.cancel)
        XCTAssertFalse(h.camera.previewing)
    }
}
