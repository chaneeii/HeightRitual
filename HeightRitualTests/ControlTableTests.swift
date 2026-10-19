import XCTest
@testable import HeightRitual

/// One test per row of the control table in SPEC section 6, plus the mode switch line under it.
@MainActor
final class ControlTableTests: XCTestCase {

    // Row: M1, R1 who is it? — knob and Left / Right move the highlight, Confirm opens.
    func testWhoIsIt() {
        let h = Harness()
        let s = h.state

        s.handle(.mode(.make))
        XCTAssertEqual(s.route, .makeWho)
        XCTAssertEqual(s.whoTileCount, 3, "Nora, Leo and the + tile")
        s.handle(.knob(1))
        XCTAssertEqual(s.highlight, 1)
        s.handle(.knob(5))
        XCTAssertEqual(s.highlight, 2, "stops at the + tile")
        s.handle(.left)
        XCTAssertEqual(s.highlight, 1)
        s.handle(.right)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .memberEdit(nil), "Confirm on + opens A1")
        s.handle(.cancel)
        XCTAssertEqual(s.route, .makeWho)
        s.handle(.knob(-9))
        XCTAssertEqual(s.highlight, 0)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .makeFilm(.ready))
        XCTAssertEqual(s.currentMember, h.nora)

        s.handle(.mode(.memory))
        XCTAssertEqual(s.route, .memoryWho)
        XCTAssertEqual(s.whoTileCount, 2, "no + tile in Memory")
        s.handle(.right)
        s.handle(.confirm)
        XCTAssertEqual(s.route, .memoryWall)
        XCTAssertEqual(s.currentMember?.name, "Leo")
        XCTAssertEqual(s.recordIndex, 3, "newest record selected")
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
        XCTAssertEqual(s.route, .makeWho)
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
        XCTAssertEqual(s.route, .memoryWho)

        s.handle(.confirm)
        s.handle(.record)
        XCTAssertEqual(s.route, .memoryWall, "no filming from Memory; only Make films")
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

    func testSettingsLanguageAndPermissions() {
        let h = Harness()
        let s = h.state
        s.settings.language = .system
        s.openSettings()
        s.handle(.knob(SettingsTile.language.rawValue))
        s.handle(.confirm)
        XCTAssertEqual(s.route, .settings(.language))
        XCTAssertEqual(s.wallModel.kind, .settingsLanguage)
        XCTAssertEqual(s.languageHighlight, .system, "starts on the saved language")
        s.handle(.right)
        s.handle(.knob(3))
        XCTAssertEqual(s.languageHighlight, .sv)
        s.handle(.right)
        XCTAssertEqual(s.languageHighlight, .sv, "stops at the last language")
        s.handle(.cancel)
        XCTAssertEqual(s.settings.language, .system, "Back leaves the language unchanged")
        s.handle(.confirm)
        s.handle(.right)
        s.handle(.confirm)
        XCTAssertEqual(s.settings.language, .en)
        XCTAssertEqual(s.route, .settings(.list), "back to the grid after choosing")
        s.settings.language = .system

        s.handle(.knob(SettingsTile.permissions.rawValue - SettingsTile.language.rawValue))
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

    func testLanguageChosenOnThePhoneGoesBack() {
        let h = Harness()
        let s = h.state
        s.openSettings()
        s.openSettingsPage(.language)
        s.chooseLanguage(.ko)
        XCTAssertEqual(s.settings.language, .ko)
        XCTAssertEqual(s.route, .settings(.list))
        s.settings.language = .system
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

    // Line under the table: the mode switch on every screen.
    func testModeSwitch() {
        let h = Harness()
        let s = h.state

        XCTAssertEqual(s.route, .memoryWho, "the app opens on Memory, R1")
        XCTAssertEqual(s.mode, .memory)
        s.handle(.mode(.memory))
        XCTAssertEqual(s.route, .memoryWho)
        s.handle(.mode(.make))
        XCTAssertEqual(s.route, .makeWho)

        s.handle(.confirm)
        s.handle(.mode(.make))
        XCTAssertEqual(s.route, .makeFilm(.ready), "the same position again, as sent on reconnect, is ignored")

        s.openSettings()
        s.handle(.mode(.memory))
        XCTAssertEqual(s.route, .memoryWho, "works from Settings too")

        // Leaving Make with an unsaved clip discards it and says so for two seconds.
        h.openHeight()
        XCTAssertNotNil(s.draft)
        s.handle(.mode(.memory))
        XCTAssertEqual(s.route, .memoryWho)
        XCTAssertNil(s.draft)
        XCTAssertEqual(s.notice, "Not saved")
        h.scheduler.advance(2)
        XCTAssertNil(s.notice)

        // Leaving from filming also discards.
        h.openFilm()
        s.handle(.record)
        h.scheduler.advance(4)
        s.handle(.mode(.memory))
        XCTAssertFalse(h.camera.recording)
        XCTAssertEqual(s.notice, "Not saved")
    }
}
