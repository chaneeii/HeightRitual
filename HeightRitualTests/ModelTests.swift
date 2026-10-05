import XCTest
@testable import HeightRitual

@MainActor
final class ModelTests: XCTestCase {

    func testHeightText() {
        XCTAssertEqual(HeightFormatter.text(1210, unit: .cm), "121.0 cm")
        XCTAssertEqual(HeightFormatter.text(1215, unit: .cm), "121.5 cm")
        // 1213 mm = 47.76 in -> 47 3/4 in
        XCTAssertEqual(HeightFormatter.text(1213, unit: .ftin), "3 ft 11 3/4 in")
        XCTAssertEqual(HeightFormatter.text(1219, unit: .ftin), "4 ft 0 in")
        XCTAssertEqual(HeightFormatter.difference(50, unit: .cm), "+5.0 cm")
        XCTAssertEqual(HeightFormatter.difference(-51, unit: .ftin), "-2 in")
    }

    func testHeightStepsAndLimits() {
        XCTAssertEqual(HeightFormatter.step(1212, by: 1, unit: .cm, coarse: false), 1215, "snaps to 0.5 cm")
        XCTAssertEqual(HeightFormatter.step(1210, by: -1, unit: .cm, coarse: true), 1200)
        XCTAssertEqual(HeightFormatter.step(405, by: -3, unit: .cm, coarse: true), 400)
        XCTAssertEqual(HeightFormatter.step(2195, by: 5, unit: .cm, coarse: false), 2200)
        // 1 ft = 304.8 mm; a quarter inch is 6.35 mm.
        XCTAssertEqual(HeightFormatter.step(1219, by: 1, unit: .ftin, coarse: false), 1226)
        XCTAssertEqual(HeightFormatter.step(1219, by: 1, unit: .ftin, coarse: true), 1245)
    }

    func testHeightInFeetOnTheHeightScreen() {
        let h = Harness()
        h.state.settings.unit = .ftin
        h.openHeight(estimateMM: 1219)
        h.state.handle(.knob(1))
        XCTAssertEqual(h.state.draft?.heightMM, 1226, "knob steps 1/4 in")
        h.state.handle(.right)
        XCTAssertEqual(h.state.draft?.heightMM, 1251, "Right steps 1 in")
    }

    func testEstimate() {
        let camera = CameraPosition(floorY: 0.9, y100: 0.5)
        // Head at 0.42: (0.9 - 0.42) * 100 / 0.4 = 120 cm
        XCTAssertEqual(HeightEstimator.estimateMM(headY: 0.42, camera: camera), 1200)
        // 120.3 cm rounds to 120.5
        XCTAssertEqual(HeightEstimator.estimateMM(headY: 0.4188, camera: camera), 1205)
        XCTAssertNil(HeightEstimator.estimateMM(headY: 0.42, camera: nil))
        XCTAssertNil(HeightEstimator.estimateMM(headY: 0.85, camera: camera), "below 40 cm")
        XCTAssertNil(HeightEstimator.estimateMM(headY: -0.1, camera: camera), "above 220 cm")
    }

    func testHeightFieldStartValue() {
        let h = Harness()
        h.openHeight(estimateMM: nil)
        XCTAssertEqual(h.state.draft?.heightMM, 1210, "no estimate: Nora's last height")
        XCTAssertFalse(h.state.showsEstimateNote)

        let first = Harness()
        first.state.store.addMember(name: "Ada")
        first.state.handle(.mode(.make))
        first.state.handle(.knob(2))
        first.state.handle(.confirm)
        first.state.handle(.record)
        first.scheduler.advance(3)
        first.state.handle(.record)
        first.state.finishProcessing(ProcessedClip())
        XCTAssertNil(first.state.draft?.heightMM, "first record without an estimate starts empty")
        first.state.handle(.confirm)
        XCTAssertEqual(first.state.route, .makeHeight(.editing), "cannot save an empty field")
    }

    func testNobodyFound() {
        let h = Harness()
        h.filmAndStop()
        h.state.finishProcessing(nil)
        XCTAssertEqual(h.state.route, .makeHeight(.noPerson))
        h.state.handle(.confirm)
        XCTAssertEqual(h.state.route, .makeFilm(.ready), "Retake")
    }

    func testStoreSampleFamilyAndDeleteEverything() {
        let h = Harness()
        let store = h.state.store
        XCTAssertEqual(store.members.map(\.name), ["Nora", "Leo"])
        XCTAssertEqual(store.records(for: store.members[0].id).count, 6)
        XCTAssertEqual(store.records(for: store.members[1].id).count, 4)

        h.state.settings.wall.ptPerCM = 7
        h.state.deleteEverything()
        XCTAssertTrue(store.members.isEmpty)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(h.state.settings.wall.ptPerCM, 7, "setup values stay")

        let reopened = Store(directory: h.directory)
        XCTAssertTrue(reopened.members.isEmpty, "an emptied store does not refill with the sample family")
    }

    func testStoreSavesClipFiles() throws {
        let h = Harness()
        let store = h.state.store
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data([1, 2, 3]).write(to: temp)
        let record = store.addRecord(memberID: store.members[0].id, heightMM: 1250, source: .estimated,
                                     clip: ProcessedClip(videoURL: temp, bodyRatio: 0.8, floorRatio: 0.05))
        let saved = try XCTUnwrap(store.mediaURL(record.videoFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertEqual(Store(directory: h.directory).record(record.id)?.bodyRatio, 0.8)

        store.deleteRecord(record.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
    }

    func testCalibration() {
        let wall = Calibration(floorPt: 40, ptPerCM: 5, shiftPt: 0, rotation: 0)
        XCTAssertEqual(wall.y(cm: 100, imageHeight: 1080), 540)
        XCTAssertEqual(wall.visibleTopCM(imageHeight: 1080), 208)
        XCTAssertEqual(Calibration(rotation: 90).logicalSize(for: CGSize(width: 1920, height: 1080)),
                       CGSize(width: 1080, height: 1920))
    }
}
