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
        XCTAssertEqual(HeightFormatter.step(1212, by: 1, unit: .cm, coarse: false, fineMM: 1), 1213, "the knob: 0.1 cm")
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

    func testHeightStepHintUntilFirstUse() {
        let h = Harness()
        h.openHeight(estimateMM: 1219)
        XCTAssertFalse(h.state.settings.heightStepsLearned, "hint shows on first use")
        h.state.setDraftHeight(1230)
        XCTAssertFalse(h.state.settings.heightStepsLearned, "dragging the dial does not count")
        h.state.handle(.knob(1))
        XCTAssertTrue(h.state.settings.heightStepsLearned)
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
        first.state.handle(.knob(2))
        first.confirm()
        first.confirm()
        first.state.handle(.record)
        first.scheduler.advance(1)
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
        let wall = Calibration(floorPt: 40, ptPerCM: 5)
        XCTAssertEqual(wall.y(cm: 100, imageHeight: 1080), 540)
        XCTAssertEqual(wall.visibleTopCM(imageHeight: 1080), 208)
        XCTAssertEqual(Calibration().logicalSize(for: CGSize(width: 1920, height: 1080)),
                       CGSize(width: 1080, height: 1920))
    }

    /// The projector lies on its side, so a 1920 x 1080 picture is 1080 wide and 1920 tall on the wall.
    func testPortraitStrip() {
        let screen = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(Calibration().stripSize(for: screen), CGSize(width: 1080, height: 1920))
    }

    // Nobody found: Retake, or keep the clip as filmed for testing.
    func testNobodyFoundCanKeepTheClip() throws {
        let h = Harness()
        h.filmAndStop()
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data([1]).write(to: raw)
        h.state.finishProcessing(ProcessedClip(rawVideoURL: raw, duration: 5, personFound: false))
        XCTAssertEqual(h.state.route, .makeHeight(.noPerson))
        h.state.useClipWithoutPerson()
        XCTAssertEqual(h.state.route, .makeHeight(.editing))
        XCTAssertEqual(h.state.draft?.heightMM, 1210, "starts at the last height")
        h.state.handle(.confirm)
        let saved = try XCTUnwrap(h.state.store.records(for: h.nora.id).last)
        XCTAssertNotNil(saved.rawVideoFile)
        XCTAssertNil(saved.videoFile)
        XCTAssertEqual(saved.duration, 5)
        XCTAssertNotNil(h.state.clipURL(saved), "Memory plays the clip as filmed")
    }

    func testBackgroundChoosesTheClip() throws {
        let h = Harness()
        let store = h.state.store
        let cut = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data([1]).write(to: cut)
        try Data([2]).write(to: raw)
        let record = store.addRecord(memberID: h.nora.id, heightMM: 1250, source: .estimated,
                                     clip: ProcessedClip(videoURL: cut, bodyRatio: 0.9, floorRatio: 0.02,
                                                         rawVideoURL: raw, rawBodyRatio: 0.5, rawFloorRatio: 0.1,
                                                         clipAspect: 0.4, rawAspect: 0.5625, duration: 4.2))
        XCTAssertEqual(h.state.clipURL(record)?.lastPathComponent, record.videoFile, "cut-out by default")
        h.state.setShowBackground(true)
        XCTAssertEqual(h.state.clipURL(record)?.lastPathComponent, record.rawVideoFile)

        h.openMemoryWall()
        let figure = try XCTUnwrap(h.state.wallModel.figure)
        XCTAssertTrue(figure.hasClip)
        XCTAssertEqual(figure.bodyRatio, 0.5, "raw clip's layout numbers with the background on")
        h.state.setShowBackground(false)
        XCTAssertEqual(h.state.wallModel.figure?.bodyRatio, 0.9)
    }

    func testAutoPlayUsesClipLength() throws {
        let h = Harness()
        let cut = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data([1]).write(to: cut)
        h.state.store.addRecord(memberID: h.nora.id, heightMM: 1250, source: .edited,
                                clip: ProcessedClip(videoURL: cut, duration: 4))
        h.openMemoryWall()
        h.state.handle(.autoPlayToggle)
        h.scheduler.advance(AppState.stillSeconds * 6)   // the six sample records
        XCTAssertEqual(h.state.recordIndex, 6, "the filmed record")
        h.scheduler.advance(3.9)
        XCTAssertEqual(h.state.recordIndex, 6, "shown for its clip's length")
        h.scheduler.advance(0.2)
        XCTAssertEqual(h.state.recordIndex, 0)
    }

    // Turning the knob moves to another record at once, even in the middle of a clip.
    func testKnobMovesDuringAClip() throws {
        let h = Harness()
        let cut = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data([1]).write(to: cut)
        h.state.store.addRecord(memberID: h.nora.id, heightMM: 1250, source: .edited,
                                clip: ProcessedClip(videoURL: cut, duration: 5))
        h.openMemoryWall()
        let newest = h.state.recordIndex
        h.scheduler.advance(1)                      // one second into the newest clip
        h.state.handle(.knob(-1))
        XCTAssertEqual(h.state.recordIndex, newest - 1, "manual: moves straight away")

        h.state.handle(.autoPlayToggle)
        h.scheduler.advance(0.5)                    // auto play, half a second into a record
        let playing = h.state.recordIndex
        h.state.handle(.knob(1))
        XCTAssertEqual(h.state.recordIndex, min(playing + 1, h.state.currentRecords.count - 1),
                       "auto play: stops and moves straight away")
        XCTAssertFalse(h.state.isAutoPlaying)
    }

    // R3 (SPEC 12, R4): correct one record's height, then delete it.
    func testRecordDetail() {
        let h = Harness()
        h.openMemoryWall()
        let record = h.state.selectedRecord!
        h.state.openRecord(record.id)
        XCTAssertEqual(h.state.route, .record(record.id))
        h.state.stepHeight(of: record.id, by: 1, coarse: false)
        XCTAssertEqual(h.state.store.record(record.id)?.heightMM, 1215)
        XCTAssertEqual(h.state.store.record(record.id)?.heightSource, .edited)
        h.state.handle(.cancel)
        XCTAssertEqual(h.state.route, .memoryWall)
        h.state.openRecord(record.id)
        h.state.deleteRecord(record.id)
        XCTAssertNil(h.state.store.record(record.id))
        XCTAssertEqual(h.state.route, .memoryWall)
        XCTAssertEqual(h.state.currentRecords.count, 5)
    }

    func testChangeRecordDate() {
        let h = Harness()
        h.openMemoryWall()
        let newest = h.state.selectedRecord!
        let early = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2019, month: 5, day: 1))!
        h.state.changeDate(of: newest.id, to: early)
        XCTAssertEqual(h.state.currentRecords.first?.id, newest.id, "now the oldest")
        XCTAssertEqual(h.state.selectedRecord?.id, newest.id, "still selected")
        h.state.changeDate(of: newest.id, to: .now.addingTimeInterval(86_400 * 30))
        XCTAssertLessThanOrEqual(h.state.store.record(newest.id)!.date, .now, "no dates in the future")
    }

    func testMarksAboveAClipWithItsBackground() throws {
        let h = Harness()
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data([1]).write(to: raw)
        h.state.store.addRecord(memberID: h.nora.id, heightMM: 1250, source: .edited,
                                clip: ProcessedClip(rawVideoURL: raw, personFound: false))
        h.openMemoryWall()
        XCTAssertEqual(h.state.wallModel.figure?.opaque, true, "only the clip as filmed exists")
    }
}
