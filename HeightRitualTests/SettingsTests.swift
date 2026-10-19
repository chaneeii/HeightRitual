import XCTest
@testable import HeightRitual

/// Milestone 3: settings, setup and the first-start wizard (SPEC 7, 12).
@MainActor
final class SettingsTests: XCTestCase {

    func testWallRotationDefaultsToOnItsSide() {
        XCTAssertEqual(Calibration().rotation, -90, "the group's projector lies on its side")
    }

    // S4: switching units changes every shown height, never a stored one.
    func testUnitSwitch() {
        let h = Harness()
        let s = h.state
        h.openMemoryWall()
        let stored = s.store.records.map(\.heightMM)
        XCTAssertTrue(s.wallModel.marks.allSatisfy { $0.label.hasSuffix(" cm") })

        s.settings.unit = .ftin
        XCTAssertTrue(s.wallModel.marks.allSatisfy { $0.label.hasSuffix(" in") })
        XCTAssertEqual(s.wallModel.caption, "Nora, Aug 2025, 3 ft 11 3/4 in")
        XCTAssertEqual(s.store.records.map(\.heightMM), stored)

        s.settings.unit = .cm
        XCTAssertEqual(s.wallModel.caption, "Nora, Aug 2025, 121.0 cm")
    }

    func testSettingsAreRemembered() {
        let suite = "test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let first = SettingsStore(defaults: defaults)
        first.unit = .ftin
        first.wall.ptPerCM = 6.5
        first.camera = CameraPosition(floorY: 0.9, y100: 0.5)
        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.unit, .ftin)
        XCTAssertEqual(second.wall.ptPerCM, 6.5)
        XCTAssertEqual(second.camera, CameraPosition(floorY: 0.9, y100: 0.5))
        defaults.removePersistentDomain(forName: suite)
    }

    // W: runs on first start; Next and Skip move on; the last step goes Home.
    func testWizard() {
        let h = Harness(setupDone: false)
        let s = h.state
        XCTAssertEqual(s.route, .wizard(.welcome), "what the app is, before any setup")
        XCTAssertEqual(s.wallModel.kind, .idle)
        s.wizardNext()
        XCTAssertEqual(s.route, .wizard(.permissions))
        XCTAssertEqual(s.wallModel.kind, .idle)
        s.wizardNext()
        XCTAssertEqual(s.route, .wizard(.fitToWall))
        XCTAssertEqual(s.wallModel.kind, .ruler)
        s.wizardNext()
        XCTAssertEqual(s.route, .wizard(.cameraPosition))
        XCTAssertEqual(s.wallModel.kind, .cameraLines)
        XCTAssertFalse(s.settings.wizardDone)
        s.wizardNext()
        XCTAssertEqual(s.route, .home)
        XCTAssertTrue(s.settings.wizardDone)

        XCTAssertEqual(Harness(setupDone: true).state.route, .home, "not again once done")
    }

    func testSettingsPagesAndBack() {
        let h = Harness()
        let s = h.state
        h.openMemoryWall()
        s.openSettings()
        XCTAssertEqual(s.route, .settings(.list))
        XCTAssertEqual(s.wallModel.kind, .settingsMenu, "the wall shows the settings as tiles")
        s.openSettingsPage(.units)
        XCTAssertEqual(s.wallModel.kind, .settingsUnits, "the projector shows its own Units page")
        s.handle(.cancel)
        XCTAssertEqual(s.route, .settings(.list), "Back on a page goes to the list")
        XCTAssertEqual(s.wallModel.kind, .settingsMenu)
        s.handle(.cancel)
        XCTAssertEqual(s.route, .memoryWall, "Back on the list returns where Settings was opened")
    }

    // D1: add, rename, recolour, remove.
    func testFamilyMembers() {
        let h = Harness()
        let s = h.state
        s.openSettings()
        s.openSettingsPage(.family)
        s.openMemberEdit(nil)
        XCTAssertEqual(s.route, .memberEdit(nil))
        s.saveMember(id: nil, name: "  Ada ", colorIndex: 3)
        XCTAssertEqual(s.route, .settings(.family))
        let ada = try! XCTUnwrap(s.store.members.last)
        XCTAssertEqual(ada.name, "Ada")
        XCTAssertEqual(ada.colorIndex, 3)

        s.openMemberEdit(ada.id)
        s.saveMember(id: ada.id, name: "Ada Lovelace", colorIndex: 4)
        XCTAssertEqual(s.store.member(ada.id)?.name, "Ada Lovelace")
        XCTAssertEqual(s.store.member(ada.id)?.colorIndex, 4)

        let nora = h.nora
        s.openMemberEdit(nora.id)
        s.deleteMember(nora.id)
        XCTAssertNil(s.store.member(nora.id))
        XCTAssertTrue(s.store.records(for: nora.id).isEmpty, "their records go too")
        XCTAssertEqual(s.route, .settings(.family))
    }

    // D2: delete everything keeps setup values; the sample family can be loaded again.
    func testDeleteEverythingAndSampleFamily() throws {
        let h = Harness()
        let s = h.state
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data([1]).write(to: temp)
        s.store.addRecord(memberID: h.nora.id, heightMM: 1250, source: .edited, clip: ProcessedClip(videoURL: temp))
        s.settings.wall.floorPt = 77
        s.settings.camera = CameraPosition(floorY: 0.9, y100: 0.5)

        s.openSettings()
        s.deleteEverything()
        XCTAssertTrue(s.store.members.isEmpty)
        XCTAssertTrue(s.store.records.isEmpty)
        let media = (try? FileManager.default.contentsOfDirectory(atPath: s.store.mediaDirectory.path)) ?? []
        XCTAssertTrue(media.isEmpty, "media folder empty")
        XCTAssertEqual(s.settings.wall.floorPt, 77)
        XCTAssertNotNil(s.settings.camera)

        s.handle(.cancel)
        XCTAssertEqual(s.route, .home)
        XCTAssertEqual(s.homeCardCount, 1, "only the Add card")

        s.loadSampleFamily()
        XCTAssertEqual(s.store.members.map(\.name), ["Nora", "Leo"])
    }

    func testDeleteEverythingFromMemoryReturnsToWho() {
        let h = Harness()
        let s = h.state
        h.openMemoryWall()
        s.openSettings()
        s.deleteEverything()
        s.handle(.cancel)
        XCTAssertEqual(s.route, .home, "the member shown before is gone")
    }

    func testLastControlForTheControllerPage() {
        let h = Harness()
        h.controller.onEvent?(.knob(-2))
        XCTAssertEqual(h.state.lastControl, .knob(-2))
    }

    // Navigation drawn from the route: the system back button sends Cancel / Back.
    func testNavigationPaths() {
        let h = Harness()
        let s = h.state
        h.openFilm()
        XCTAssertEqual(s.makePath, [.film])
        s.popped(1)
        XCTAssertEqual(s.route, .memberMenu)
        XCTAssertEqual(s.makePath, [])
        s.handle(.cancel)

        h.openMemoryWall()
        XCTAssertEqual(s.memoryPath, [.wall])
        s.popped(1)
        XCTAssertEqual(s.route, .memberMenu)
        s.handle(.cancel)

        s.openSettings()
        XCTAssertTrue(s.showsSettings)
        s.setSettingsPath([.page(.family)])
        XCTAssertEqual(s.route, .settings(.family))
        s.setSettingsPath([.page(.family), .member(h.nora.id)])
        XCTAssertEqual(s.route, .memberEdit(h.nora.id))
        XCTAssertTrue(s.showsSettings, "A1 from Family stays inside the Settings sheet")
        XCTAssertFalse(s.showsMemberSheet)
        s.setSettingsPath([.page(.family)])
        XCTAssertEqual(s.route, .settings(.family))
        s.setSettingsPath([])
        XCTAssertEqual(s.route, .settings(.list))
        s.dismissSettings()
        XCTAssertEqual(s.route, .home)
        XCTAssertFalse(s.showsSettings)

        s.openTile(s.store.members.count)
        h.scheduler.advance(AppState.confirmSeconds)
        XCTAssertEqual(s.navigationPath, [.addMember], "adding a member is pushed above Home")
        s.popped(1)
        XCTAssertEqual(s.route, .home)
    }

    func testAppearanceIsRemembered() {
        let suite = "test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        SettingsStore(defaults: defaults).appearance = .light
        XCTAssertEqual(SettingsStore(defaults: defaults).appearance, .light)
        defaults.removePersistentDomain(forName: suite)
    }

    func testSetUpLater() {
        let h = Harness(setupDone: false)
        h.state.skipWizard()
        XCTAssertEqual(h.state.route, .home)
        XCTAssertTrue(h.state.settings.wizardDone)
        h.state.startWizard()
        XCTAssertEqual(h.state.route, .wizard(.permissions), "the banner goes straight to the setup steps")
    }

    // The gear on the member menu edits that member; the card shows a colour or the newest photo.
    func testMemberCardStyle() throws {
        let h = Harness()
        let s = h.state
        h.confirm()
        s.openMemberEdit(s.currentMember?.id)
        XCTAssertEqual(s.route, .memberEdit(h.nora.id))
        XCTAssertTrue(s.showsMemberSheet)
        XCTAssertEqual(h.nora.card, .photo, "the newest photo by default")
        XCTAssertNil(s.store.latestPhotoURL(for: h.nora.id), "sample records have no photo")

        s.saveMember(id: h.nora.id, name: "Nora", colorIndex: 3, cardStyle: .colour)
        XCTAssertEqual(s.route, .memberMenu, "back to the menu")
        XCTAssertEqual(h.nora.card, .colour)
        XCTAssertEqual(h.nora.colorIndex, 3)

        let poster = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([1]).write(to: poster)
        s.store.addRecord(memberID: h.nora.id, heightMM: 1250, source: .edited, clip: ProcessedClip(posterURL: poster))
        XCTAssertNotNil(s.store.latestPhotoURL(for: h.nora.id), "a new record brings a photo")
    }
}
