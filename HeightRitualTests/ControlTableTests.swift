import XCTest
@testable import HeightRitual

/// One test per row of the control table in SPEC section 6, plus the mode switch line under it.
@MainActor
final class ControlTableTests: XCTestCase {

    // Row: H, the Home wheel — knob and Left / Right turn it, Confirm opens the card after the
    // check has turned green. The Add card comes last.
    func testHomeWheel() {
        let h = Harness()
        let s = h.state

        XCTAssertEqual(s.route, .home, "the app opens on Home")
        XCTAssertEqual(s.homeCardCount, 3, "Nora, Leo and the Add card")
        s.handle(.knob(1))
        XCTAssertEqual(s.highlight, 1)
        s.handle(.knob(5))
        XCTAssertEqual(s.highlight, 2, "stops at the Add card")
        XCTAssertTrue(s.highlightsAddCard)
        s.handle(.left)
        XCTAssertEqual(s.highlight, 1)
        s.handle(.knob(-9))
        XCTAssertEqual(s.highlight, 0)

        s.handle(.confirm)
        XCTAssertTrue(s.confirmFlash, "the check turns green first")
        XCTAssertEqual(s.route, .home)
        s.handle(.right)
        XCTAssertEqual(s.highlight, 0, "no turning while the choice opens")
        h.scheduler.advance(AppState.confirmSeconds)
        XCTAssertFalse(s.confirmFlash)
        XCTAssertEqual(s.route, .memberMenu)
        XCTAssertEqual(s.currentMember, h.nora)
    }

    // Row: H1, the member menu — Left / Right or the knob choose, Confirm opens, Cancel goes back.
    func testMemberMenu() {
        let h = Harness()
        let s = h.state

        h.confirm()
        XCTAssertEqual(s.menuChoice, .record)
        s.handle(.right)
        XCTAssertEqual(s.menuChoice, .lookback)
        s.handle(.knob(-1))
        XCTAssertEqual(s.menuChoice, .record)
        s.handle(.mode(.memory))
        XCTAssertEqual(s.menuChoice, .lookback, "the mode switch preselects")
        s.handle(.cancel)
        XCTAssertEqual(s.route, .home)
        XCTAssertEqual(s.highlight, 0, "the wheel keeps the member")

        s.handle(.right)
        h.confirm()
        XCTAssertEqual(s.currentMember?.name, "Leo")
        s.handle(.right)
        h.confirm()
        XCTAssertEqual(s.route, .memoryWall)
        XCTAssertEqual(s.recordIndex, 3, "newest record selected")
        s.handle(.cancel)
        XCTAssertEqual(s.route, .memberMenu, "back from Lookback is the menu")
        XCTAssertEqual(s.menuChoice, .lookback)

        s.handle(.record)
        h.scheduler.advance(AppState.confirmSeconds)
        XCTAssertEqual(s.route, .makeFilm(.ready), "Record on the box goes straight to filming")
    }

    // Row: A2, add member — the letter wheel has no ends; Confirm presses the key in the middle.
    func testAddMember() {
        let h = Harness()
        let s = h.state

        s.handle(.knob(2))
        h.confirm()
        XCTAssertEqual(s.route, .addMember)
        XCTAssertEqual(LetterKey.at(s.letterIndex), .letter("A"))
        s.handle(.confirm)
        s.handle(.right)
        s.handle(.confirm)
        XCTAssertEqual(s.nameDraft, "AB")
        s.handle(.knob(-3))
        XCTAssertEqual(LetterKey.at(s.letterIndex), .delete)
        s.handle(.confirm)
        XCTAssertEqual(s.nameDraft, "A")
        s.handle(.left)
        XCTAssertEqual(LetterKey.at(s.letterIndex), .letter("Z"), "past Delete comes Z")
        s.handle(.confirm)
        s.handle(.knob(2))
        XCTAssertEqual(LetterKey.at(s.letterIndex), .save)
        h.confirm()
        XCTAssertEqual(s.route, .home)
        XCTAssertEqual(s.store.members.last?.name, "Az")
        XCTAssertEqual(s.highlight, 2, "the new member is in the middle")

        s.handle(.knob(5))
        h.confirm()
        s.handle(.cancel)
        XCTAssertEqual(s.route, .home, "Cancel leaves without saving")
        XCTAssertEqual(s.store.members.count, 3)

        s.openTile(3)
        h.scheduler.advance(AppState.confirmSeconds)
        s.handle(.knob(-1))
        h.confirm()
        XCTAssertEqual(s.route, .addMember, "Save with no letters does nothing")
    }

    // Row: M2 film: ready — Confirm or Record starts the countdown, Cancel goes back to M1.
    func testFilmReady() {
        let h = Harness()
        let s = h.state

        h.openFilm()
        XCTAssertTrue(h.camera.previewing)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .makeFilm(.countdown(3)))

        s.handle(.cancel)
        s.handle(.record)
        XCTAssertEqual(s.route, .makeFilm(.countdown(3)))

        s.handle(.cancel)
        XCTAssertEqual(s.route, .makeFilm(.ready))
        s.handle(.cancel)
        XCTAssertEqual(s.route, .memberMenu)
        XCTAssertFalse(h.camera.previewing)
    }

    // Row: M2 film: countdown, filming — Cancel discards, Record stops early.
    func testFilmCountdownAndFilming() {
        let h = Harness()
        let s = h.state

        h.openFilm()
        s.handle(.record)
        h.scheduler.advance(1)
        XCTAssertEqual(s.route, .makeFilm(.countdown(2)))
        s.handle(.cancel)
        XCTAssertEqual(s.route, .makeFilm(.ready))
        h.scheduler.advance(10)
        XCTAssertEqual(s.route, .makeFilm(.ready), "cancelled countdown does not start filming")

        s.handle(.record)
        h.scheduler.advance(3)
        XCTAssertEqual(s.route, .makeFilm(.filming(secondsLeft: 5)))
        XCTAssertTrue(h.camera.recording)
        h.scheduler.advance(2)
        XCTAssertEqual(s.route, .makeFilm(.filming(secondsLeft: 3)))
        s.handle(.cancel)
        XCTAssertEqual(s.route, .makeFilm(.ready))
        XCTAssertFalse(h.camera.recording)

        s.handle(.record)
        h.scheduler.advance(4)
        s.handle(.record)
        XCTAssertEqual(s.route, .makeHeight(.cuttingOut(progress: 0)), "Record stops early")

        // Without a press, filming ends by itself after 5 s.
        s.handle(.cancel)
        s.handle(.record)
        h.scheduler.advance(3 + 5)
        XCTAssertEqual(s.route, .makeHeight(.cuttingOut(progress: 0)))
    }

    // Row: M3 height: cutting out — Cancel discards and goes back to M2.
    func testCuttingOut() {
        let h = Harness()
        let s = h.state

        h.filmAndStop()
        s.handle(.confirm)
        s.handle(.knob(3))
        XCTAssertEqual(s.route, .makeHeight(.cuttingOut(progress: 0)), "only Cancel acts here")
        s.handle(.cancel)
        XCTAssertEqual(s.route, .makeFilm(.ready))
        s.finishProcessing(ProcessedClip(estimatedMM: 1200))
        XCTAssertEqual(s.route, .makeFilm(.ready), "a late result after Cancel is ignored")
        XCTAssertNil(s.draft)
    }

    // Row: M3 height — knob +/- 0.5 cm, Left / Right -/+ 1 cm, Confirm saves, Cancel retakes.
    func testHeight() {
        let h = Harness()
        let s = h.state
        let before = s.store.records(for: h.nora.id).count

        h.openHeight(estimateMM: 1225)
        XCTAssertEqual(s.route, .makeHeight(.editing))
        XCTAssertEqual(s.draft?.heightMM, 1225)
        XCTAssertTrue(s.showsEstimateNote)

        s.handle(.knob(1))
        XCTAssertEqual(s.draft?.heightMM, 1230)
        XCTAssertFalse(s.showsEstimateNote, "a changed field shows no note")
        s.handle(.knob(-3))
        XCTAssertEqual(s.draft?.heightMM, 1215)
        s.handle(.right)
        XCTAssertEqual(s.draft?.heightMM, 1225)
        s.handle(.left)
        s.handle(.left)
        XCTAssertEqual(s.draft?.heightMM, 1205)

        s.handle(.cancel)
        XCTAssertEqual(s.route, .makeFilm(.ready), "Cancel is Retake")
        XCTAssertNil(s.draft)

        h.state.handle(.record)
        h.scheduler.advance(3)
        s.handle(.record)
        s.finishProcessing(ProcessedClip(estimatedMM: 1225))
        s.handle(.knob(2))
        s.handle(.confirm)
        let records = s.store.records(for: h.nora.id)
        XCTAssertEqual(records.count, before + 1)
        XCTAssertEqual(records.last?.heightMM, 1235)
        XCTAssertEqual(records.last?.heightSource, .edited)
        XCTAssertEqual(s.route, .memoryWall, "Save opens Memory")
        XCTAssertEqual(s.mode, .memory)
        XCTAssertEqual(s.selectedRecord?.id, records.last?.id, "with the new record selected")
        XCTAssertNil(s.notice)
    }

    // Row: R2 wall: manual — knob and Left / Right move, Confirm replays, Cancel back to R1,
    // Record does nothing (changed 5 Oct: only Make films), Auto play starts auto play.
    func testMemoryManual() {
        let h = Harness()
        let s = h.state

        h.openMemoryWall()
        XCTAssertEqual(s.recordIndex, 5)
        s.handle(.knob(-2))
        XCTAssertEqual(s.recordIndex, 3)
        s.handle(.knob(-10))
        XCTAssertEqual(s.recordIndex, 0)
        s.handle(.right)
        XCTAssertEqual(s.recordIndex, 1)
        s.handle(.left)
        XCTAssertEqual(s.recordIndex, 0)

        let replays = s.replayCount
        s.handle(.confirm)
        XCTAssertEqual(s.replayCount, replays + 1)
        XCTAssertEqual(s.route, .memoryWall)

        s.handle(.cancel)
        XCTAssertEqual(s.route, .memberMenu)

        h.confirm()
        s.handle(.record)
        XCTAssertEqual(s.route, .memoryWall, "no filming from Lookback")
        XCTAssertEqual(s.mode, .memory)

        h.openMemoryWall()
        s.handle(.autoPlayToggle)
        XCTAssertTrue(s.isAutoPlaying)
        XCTAssertEqual(s.recordIndex, 0, "auto play starts at the first record")
    }

    // Row: R2 wall: auto play — knob and Left / Right stop then move; Confirm, Cancel and
    // Auto play stop.
    func testMemoryAutoPlay() {
        let h = Harness()
        let s = h.state

        h.openMemoryWall()
        s.handle(.autoPlayToggle)
        h.scheduler.advance(AppState.stillSeconds * 2)
        XCTAssertEqual(s.recordIndex, 2, "steps through records by itself")
        h.scheduler.advance(AppState.stillSeconds * 4)
        XCTAssertEqual(s.recordIndex, 0, "starts again after the newest")

        s.handle(.knob(2))
        XCTAssertFalse(s.isAutoPlaying)
        XCTAssertEqual(s.recordIndex, 2)
        h.scheduler.advance(10)
        XCTAssertEqual(s.recordIndex, 2, "stays stopped")

        s.handle(.autoPlayToggle)
        s.handle(.right)
        XCTAssertFalse(s.isAutoPlaying)
        XCTAssertEqual(s.recordIndex, 1)

        for event in [ControlEvent.confirm, .cancel, .autoPlayToggle] {
            s.handle(.autoPlayToggle)
            XCTAssertTrue(s.isAutoPlaying)
            s.handle(event)
            XCTAssertFalse(s.isAutoPlaying, "\(event) stops auto play")
            XCTAssertEqual(s.route, .memoryWall, "\(event) only stops, it does not leave")
        }
    }

    // Row: S2 fit to wall — knob changes the value, Left / Right select it, Confirm / Cancel done.
    func testFitToWall() {
        let h = Harness()
        let s = h.state
        let start = s.settings.wall

        s.openSettings()
        s.openSettingsPage(.fitToWall)
        XCTAssertEqual(s.fitValue, .floor)
        s.handle(.knob(2))
        XCTAssertEqual(s.settings.wall.floorPt, start.floorPt + 10)
        s.handle(.right)
        XCTAssertEqual(s.fitValue, .size)
        s.handle(.knob(1))
        XCTAssertEqual(s.settings.wall.ptPerCM, start.ptPerCM + 0.05, accuracy: 1e-9)
        s.fitFine = true
        s.handle(.knob(1))
        XCTAssertEqual(s.settings.wall.ptPerCM, start.ptPerCM + 0.06, accuracy: 1e-9)
        s.handle(.right)
        s.handle(.right)
        XCTAssertEqual(s.fitValue, .shift)
        s.handle(.knob(-1))
        XCTAssertEqual(s.settings.wall.shiftPt, start.shiftPt - 1)
        s.handle(.left)
        XCTAssertEqual(s.fitValue, .size)

        s.handle(.confirm)
        XCTAssertEqual(s.route, .settings(.list))
        s.openSettingsPage(.fitToWall)
        s.handle(.cancel)
        XCTAssertEqual(s.route, .settings(.list))

        s.startWizard()
        s.wizardNext()
        XCTAssertEqual(s.route, .wizard(.fitToWall))
        s.handle(.confirm)
        XCTAssertEqual(s.route, .wizard(.cameraPosition), "Done in the wizard moves to the next step")
    }

    // Leaving Make with an unsaved clip discards it and says so for two seconds.
    func testLeavingMakeDiscards() {
        let h = Harness()
        let s = h.state

        s.handle(.mode(.make))
        XCTAssertEqual(s.route, .home, "the mode switch never moves away from Home")

        h.openHeight()
        XCTAssertNotNil(s.draft)
        s.openSettings()
        XCTAssertNil(s.draft)
        XCTAssertEqual(s.notice, "Not saved")
        h.scheduler.advance(2)
        XCTAssertNil(s.notice)
        s.leaveSettings()
        XCTAssertEqual(s.route, .makeFilm(.ready))

        // Leaving from filming also discards.
        s.handle(.record)
        h.scheduler.advance(4)
        s.openSettings()
        XCTAssertFalse(h.camera.recording)
        XCTAssertEqual(s.notice, "Not saved")
    }
}
