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
        let replays = s.replayCount
        h.confirm()
        XCTAssertEqual(s.route, .memoryWall)
        XCTAssertEqual(s.recordIndex, 3, "newest record selected")
        XCTAssertEqual(s.replayCount, replays + 1, "its clip starts playing at once")
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

    // Row: M2 film: ready — Confirm or Record films at once (no countdown), Cancel goes back to
    // the member menu.
    func testFilmReady() {
        let h = Harness()
        let s = h.state

        h.openFilm()
        XCTAssertTrue(h.camera.previewing)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .makeFilm(.filming(secondsLeft: 5)))
        XCTAssertTrue(h.camera.recording)

        s.handle(.cancel)
        XCTAssertEqual(s.route, .makeFilm(.ready))
        s.handle(.record)
        XCTAssertEqual(s.route, .makeFilm(.filming(secondsLeft: 5)))

        s.handle(.cancel)
        s.handle(.cancel)
        XCTAssertEqual(s.route, .memberMenu)
        XCTAssertFalse(h.camera.previewing)
    }

    // Row: M2 filming — the seconds count down, Cancel discards, Record stops early.
    func testFilming() {
        let h = Harness()
        let s = h.state

        h.openFilm()
        s.handle(.record)
        h.scheduler.advance(2)
        XCTAssertEqual(s.route, .makeFilm(.filming(secondsLeft: 3)))
        s.handle(.cancel)
        XCTAssertEqual(s.route, .makeFilm(.ready))
        XCTAssertFalse(h.camera.recording)
        h.scheduler.advance(10)
        XCTAssertEqual(s.route, .makeFilm(.ready), "cancelled filming stays cancelled")

        s.handle(.record)
        h.scheduler.advance(1)
        s.handle(.record)
        XCTAssertEqual(s.route, .makeHeight(.cuttingOut(progress: 0)), "Record stops early")

        // Confirm (the round button) stops early too: the box has no Record button.
        s.handle(.cancel)
        s.handle(.confirm)
        h.scheduler.advance(1)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .makeHeight(.cuttingOut(progress: 0)))

        // Without a press, filming ends by itself after 5 s.
        s.handle(.cancel)
        s.handle(.record)
        h.scheduler.advance(5)
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

    // Row: M3 height — knob +/- 0.1 cm, Left / Right -/+ 1 cm, Confirm saves, Cancel retakes.
    func testHeight() {
        let h = Harness()
        let s = h.state
        let before = s.store.records(for: h.nora.id).count

        h.openHeight(estimateMM: 1225)
        XCTAssertEqual(s.route, .makeHeight(.editing))
        XCTAssertEqual(s.draft?.heightMM, 1225)
        XCTAssertTrue(s.showsEstimateNote)

        s.handle(.knob(1))
        XCTAssertEqual(s.draft?.heightMM, 1226, "0.1 cm a knob step")
        XCTAssertFalse(s.showsEstimateNote, "a changed field shows no note")
        s.handle(.knob(-11))
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
        h.scheduler.advance(1)
        s.handle(.record)
        s.finishProcessing(ProcessedClip(estimatedMM: 1225))
        s.handle(.knob(10))
        s.handle(.confirm)
        let records = s.store.records(for: h.nora.id)
        XCTAssertEqual(records.count, before + 1)
        XCTAssertEqual(records.last?.heightMM, 1235)
        XCTAssertEqual(records.last?.heightSource, .edited)
        XCTAssertEqual(s.route, .makeSaved, "Save shows Saved")
        XCTAssertEqual(s.savedRecord?.heightMM, 1235)
        h.confirm()
        XCTAssertEqual(s.route, .memoryWall, "See growth opens Lookback")
        XCTAssertEqual(s.mode, .memory)
        XCTAssertEqual(s.selectedRecord?.id, records.last?.id, "with the new record selected")
        XCTAssertNil(s.notice)
        XCTAssertTrue(s.showsLookbackHint)
        s.handle(.left)
        XCTAssertFalse(s.showsLookbackHint, "the hint goes at the first move")
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

    // Rows: S list on the projector grid and S4 units — knob / Left / Right choose, Select opens
    // or saves, Back goes back.
    func testSettingsGridAndUnits() {
        let h = Harness()
        let s = h.state
        s.settings.unit = .cm
        h.openMemoryWall()
        s.openSettings()
        XCTAssertEqual(s.settingsHighlight, .setupGuide)
        s.handle(.right)
        XCTAssertEqual(s.settingsHighlight, .family)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .settings(.list), "tiles without a projector page do nothing yet")
        s.handle(.knob(3))
        XCTAssertEqual(s.settingsHighlight, .units)
        s.handle(.left)
        s.handle(.right)
        XCTAssertEqual(s.settingsHighlight, .units)
        s.handle(.knob(-20))
        XCTAssertEqual(s.settingsHighlight, .setupGuide, "stops at the first tile")
        s.handle(.knob(4))

        s.handle(.confirm)
        XCTAssertEqual(s.route, .settings(.units))
        XCTAssertEqual(s.wallModel.kind, .settingsUnits)
        XCTAssertEqual(s.unitHighlight, .cm, "starts on the saved unit")
        s.handle(.right)
        XCTAssertEqual(s.unitHighlight, .ftin)
        XCTAssertEqual(s.settings.unit, .cm, "nothing is saved before Select")
        s.handle(.cancel)
        XCTAssertEqual(s.route, .settings(.list), "Back leaves the unit unchanged")
        XCTAssertEqual(s.settings.unit, .cm)

        s.handle(.confirm)
        s.handle(.knob(1))
        s.handle(.confirm)
        XCTAssertEqual(s.settings.unit, .ftin)
        XCTAssertEqual(s.route, .settings(.list), "back to the grid after choosing")
        XCTAssertEqual(s.settingsHighlight, .units, "the grid keeps its place")

        s.handle(.cancel)
        XCTAssertEqual(s.route, .memoryWall, "Back on the grid closes Settings")
    }

    func testSettingsPermissionsAndSetupGuide() {
        let h = Harness()
        let s = h.state
        s.openSettings()
        s.handle(.knob(SettingsTile.permissions.rawValue))
        s.handle(.confirm)
        XCTAssertEqual(s.route, .settings(.permissions))
        XCTAssertEqual(s.wallModel.kind, .settingsPermissions)
        s.handle(.right)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .settings(.permissions), "nothing to choose on Permissions")
        s.handle(.cancel)
        XCTAssertEqual(s.route, .settings(.list))

        s.handle(.knob(-20))
        XCTAssertEqual(s.settingsHighlight, .setupGuide)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .settings(.setupGuide))
        XCTAssertEqual(s.wallModel.kind, .settingsGuide, "the projector shows the setup pictures")
        s.handle(.cancel)
        XCTAssertEqual(s.route, .settings(.list))
    }

    func testCameraPositionFromTheGrid() {
        let h = Harness()
        let s = h.state
        s.openSettings()
        s.handle(.knob(SettingsTile.cameraPosition.rawValue))
        s.handle(.confirm)
        XCTAssertEqual(s.route, .settings(.cameraPosition))
        XCTAssertEqual(s.wallModel.kind, .cameraLines, "the projector shows the 0 and 100 cm lines")
        s.handle(.cancel)
        XCTAssertEqual(s.route, .settings(.list))
        XCTAssertEqual(s.settingsHighlight, .cameraPosition)
    }

    func testFitToWallFromTheGrid() {
        let h = Harness()
        let s = h.state
        let start = s.settings.wall
        s.openSettings()
        s.handle(.knob(SettingsTile.fitToWall.rawValue))
        s.handle(.confirm)
        XCTAssertEqual(s.route, .settings(.fitToWall))
        XCTAssertEqual(s.wallModel.kind, .ruler)
        XCTAssertEqual(s.fitValue, .floor)
        s.handle(.knob(1))
        XCTAssertEqual(s.settings.wall.floorPt, start.floorPt + 5)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .settings(.list), "Done goes back to the grid")
        XCTAssertEqual(s.settingsHighlight, .fitToWall)
    }

    func testUnitChosenOnThePhoneGoesBack() {
        let h = Harness()
        let s = h.state
        s.settings.unit = .cm
        s.openSettings()
        s.openSettingsPage(.units)
        s.chooseUnit(.ftin)
        XCTAssertEqual(s.settings.unit, .ftin)
        XCTAssertEqual(s.route, .settings(.list))
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
        XCTAssertEqual(s.fitValue, .size, "the last value stays selected")
        s.handle(.left)
        XCTAssertEqual(s.fitValue, .floor)

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

    // Onboarding with the controller: every step, the member it adds and its first record.
    func testOnboardingWithController() {
        let h = Harness()
        let s = h.state

        s.openSettings()
        s.startTutorial()
        XCTAssertEqual(s.route, .tutorial(.welcome))
        XCTAssertFalse(s.showsSettings, "the Settings sheet closes")
        h.confirm()
        XCTAssertEqual(s.route, .tutorial(.family))
        XCTAssertEqual(s.tutorialLearned, [.confirm], "the first Confirm teaches it")
        XCTAssertEqual(s.tutorialToast, .confirm)
        h.scheduler.advance(2)
        XCTAssertNil(s.tutorialToast, "the toast goes by itself")
        h.confirm()
        XCTAssertEqual(s.route, .tutorial(.name))
        XCTAssertNil(s.tutorialToast, "only the first use shows a toast")

        s.handle(.knob(13))                 // A + 13 = N
        s.handle(.confirm)
        s.handle(.knob(1))                  // O
        s.handle(.confirm)
        XCTAssertEqual(s.nameDraft, "NO")
        s.handle(.knob(-15))                // back to Save
        XCTAssertEqual(LetterKey.at(s.letterIndex), .save)
        h.confirm()
        XCTAssertEqual(s.route, .tutorial(.chooseRecord))
        XCTAssertEqual(s.store.members.last?.name, "No")

        s.handle(.cancel)
        XCTAssertEqual(s.route, .tutorial(.name))
        XCTAssertEqual(s.store.members.count, 2, "going back removes the member it added")
        s.handle(.confirm)
        s.handle(.knob(-1))
        h.confirm()
        XCTAssertEqual(s.store.members.last?.name, "A")

        s.handle(.right)
        h.confirm()
        XCTAssertEqual(s.route, .tutorial(.chooseRecord), "Lookback is not this step's answer")
        XCTAssertEqual(s.notice, "Choose Record to measure first")
        s.handle(.left)
        h.confirm()
        XCTAssertEqual(s.route, .tutorial(.film))
        s.handle(.confirm)
        XCTAssertEqual(s.tutorialFilmLeft, 5)
        h.scheduler.advance(5)
        XCTAssertEqual(s.route, .tutorial(.height))

        s.handle(.right)
        s.handle(.right)
        s.handle(.right)
        s.handle(.right)
        s.handle(.knob(5))
        XCTAssertEqual(s.tutorialMM, 1245)
        h.confirm()
        XCTAssertEqual(s.route, .tutorial(.saved))
        XCTAssertEqual(s.savedRecord?.heightMM, 1245)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .tutorial(.saved), "only Back moves on here")
        s.handle(.cancel)
        XCTAssertEqual(s.route, .tutorial(.chooseLookback))
        s.handle(.right)
        h.confirm()
        XCTAssertEqual(s.route, .tutorial(.lookback))
        XCTAssertEqual(s.selectedRecord?.heightMM, 1245)
        h.confirm()
        XCTAssertEqual(s.route, .tutorial(.ready))
        XCTAssertEqual(s.tutorialLearned, Set(TutorialLesson.allCases), "every control learned")
        h.confirm()
        XCTAssertEqual(s.route, .home)
        XCTAssertEqual(s.highlightedMember?.name, "A", "Home opens on the member just added")
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
