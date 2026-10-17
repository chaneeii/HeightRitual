import Foundation
import Observation
import UIKit

/// A record being made: the cut-out clip and the height field on M3.
struct MakeDraft: Equatable {
    var clip: ProcessedClip
    var heightMM: Int?
    /// True while the field still shows the estimate from the video; the note is shown only then.
    var fromEstimate: Bool
}

/// One packet on the controller test page.
struct ControlLogEntry: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    var bytes: [UInt8] = []
    /// A connection step instead of a packet.
    var note: String?

    var text: String {
        if let note { return note }
        let raw = "[" + bytes.map(String.init).joined(separator: ", ") + "]"
        guard bytes.count >= 2 else { return raw + "  too short" }
        let event = ControlEvent.from(id: bytes[0], value: Int8(bitPattern: bytes[1]))
        return raw + "  " + (event?.label ?? "unknown control")
    }
}

/// Single source of truth shared by the phone scene and the projector scene.
/// Every input arrives through `handle(_:)`; the route changes only through `go(to:)`.
@MainActor
@Observable
final class AppState {
    static let shared = AppState(
        store: Store(),
        settings: SettingsStore(),
        camera: CameraController(),
        processor: VideoCutout(),
        controller: ControllerManager(),
        scheduler: TaskScheduler()
    )

    let store: Store
    let settings: SettingsStore
    @ObservationIgnored let camera: CameraProviding
    @ObservationIgnored let processor: ClipProcessing
    @ObservationIgnored let controller: ControllerLink
    @ObservationIgnored let scheduler: Scheduling

    static let countdownSeconds = 3
    static let filmSeconds = 5
    /// How long auto play shows a record without a clip (sample records).
    static let stillSeconds = 1.5
    /// How long the check stays green before a confirmed choice opens.
    static let confirmSeconds = 0.35
    static let maxNameLength = 12

    private(set) var route: Route = .home
    /// Make while filming, Memory while looking back; nil on Home.
    private(set) var mode: Mode?
    /// The card in the middle of the Home wheel. The index after the last member is the Add card.
    private(set) var highlight = 0
    /// The highlighted choice on the member menu.
    private(set) var menuChoice: MemberAction = .record
    /// The name being built on the add-member screen, in capitals as picked.
    private(set) var nameDraft = ""
    /// Position on the letter wheel; any integer, read through `LetterKey.at(_:)`.
    private(set) var letterIndex = LetterKey.startIndex
    /// True for a moment after Confirm while the check turns green; the chosen action follows.
    private(set) var confirmFlash = false
    /// Goes up on every Confirm, so screens can play a press animation.
    private(set) var confirmCount = 0
    /// Debug builds: the phone shows the wall picture instead of its own screens.
    var debugShowsWall = false
    private(set) var memberID: UUID?
    private(set) var recordIndex = 0
    private(set) var isAutoPlaying = false
    /// Goes up each time the selected clip should start again from the beginning.
    private(set) var replayCount = 0 {
        didSet { playSelectedClip() }
    }
    /// Clips on the wall and in the phone's wall copy.
    @ObservationIgnored let wallPlayer = WallPlayer()
    private(set) var draft: MakeDraft?
    /// Short message such as "Not saved", cleared after two seconds.
    private(set) var notice: String?
    /// The last control event, shown on the controller page for testing the box.
    private(set) var lastControl: ControlEvent?
    /// Newest first, at most 50 packets from the controller.
    private(set) var controlLog: [ControlLogEntry] = []

    private(set) var fitValue: FitValue = .floor
    var fitFine = false

    var externalDisplayConnected = false
    /// Projector screen size in points. Until a projector is connected, a 1080p picture is assumed.
    var wallSize = CGSize(width: 1920, height: 1080)
    private(set) var controllerStatus: ControllerStatus = .notAllowed
    private(set) var light = LightState()

    @ObservationIgnored private var timer: ScheduledTask?
    @ObservationIgnored private var noticeTimer: ScheduledTask?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private(set) var settingsReturn: Route = .home
    @ObservationIgnored private(set) var memberEditReturn: Route = .home

    init(store: Store, settings: SettingsStore, camera: CameraProviding, processor: ClipProcessing,
         controller: ControllerLink, scheduler: Scheduling) {
        self.store = store
        self.settings = settings
        self.camera = camera
        self.processor = processor
        self.controller = controller
        self.scheduler = scheduler
        // 첫 실행: 셋업 마법사부터 (SPEC 5, W)
        if settings.wizardDone {
            route = .home
        } else {
            route = .wizard(.welcome)
        }

        controller.onEvent = { [weak self] event in self?.handle(event) }
        controller.onRaw = { [weak self] bytes in
            guard let self else { return }
            controlLog.insert(ControlLogEntry(time: .now, bytes: bytes), at: 0)
            if controlLog.count > 50 { controlLog.removeLast() }
        }
        controller.onNote = { [weak self] note in
            guard let self else { return }
            controlLog.insert(ControlLogEntry(time: .now, note: note), at: 0)
            if controlLog.count > 50 { controlLog.removeLast() }
        }
        controller.onStatus = { [weak self] status in
            guard let self else { return }
            controllerStatus = status
            if status == .connected { controller.setLight(light) }
        }
        // 권한 팝업은 마법사의 권한 단계에서 띄운다 (SPEC 5, W)
        if !(controller is ControllerManager) || !ControllerManager.needsPermission {
            controllerStatus = .searching
            controller.start()
        }
    }

    // MARK: Derived values

    var currentMember: Member? { memberID.flatMap(store.member) }

    var currentRecords: [GrowthRecord] {
        memberID.map(store.records(for:)) ?? []
    }

    var selectedRecord: GrowthRecord? {
        currentRecords.indices.contains(recordIndex) ? currentRecords[recordIndex] : nil
    }

    /// Cards on the Home wheel: every member, then the Add card.
    var homeCardCount: Int { store.members.count + 1 }

    /// The highlighted Home card is the Add card.
    var highlightsAddCard: Bool { highlight >= store.members.count }

    /// The member on the highlighted Home card.
    var highlightedMember: Member? {
        store.members.indices.contains(highlight) ? store.members[highlight] : nil
    }

    var showsEstimateNote: Bool { draft?.fromEstimate == true }

    // MARK: Input

    func handle(_ event: ControlEvent) {
        lastControl = event
        // 컨트롤러 테스트 페이지: 신호는 기록만 하고 화면은 그대로 둔다
        if route == .settings(.controller) { return }
        if case .mode(let next) = event {
            switchMode(to: next)
            return
        }
        switch route {
        case .home:
            handleHome(event)
        case .memberMenu:
            handleMenu(event)
        case .addMember:
            handleAddMember(event)
        case .makeFilm(let state):
            handleFilm(event, state)
        case .makeHeight(let state):
            handleHeight(event, state)
        case .memoryWall:
            if isAutoPlaying { handleAutoPlay(event) } else { handleManual(event) }
        case .record:
            if event == .cancel { go(to: .memoryWall) }
        case .memberEdit:
            if event == .cancel { closeMemberEdit() }
        case .settings(.fitToWall), .wizard(.fitToWall):
            handleFit(event)
        case .settings(let page):
            if event == .cancel { page == .list ? leaveSettings() : go(to: .settings(.list)) }
        case .wizard:
            break
        }
    }

    /// The slide switch. Members come first now, so it only preselects Record (Make) or Lookback
    /// (Memory) on the member menu; it never moves the user away from their screen.
    private func switchMode(to next: Mode) {
        guard route == .memberMenu else { return }
        menuChoice = next == .make ? .record : .lookback
    }

    private func handleHome(_ event: ControlEvent) {
        guard !confirmFlash else { return }
        switch event {
        case .knob(let steps): moveHighlight(by: steps)
        case .left: moveHighlight(by: -1)
        case .right: moveHighlight(by: 1)
        case .confirm: openHighlighted()
        default: break
        }
    }

    private func handleMenu(_ event: ControlEvent) {
        guard !confirmFlash else { return }
        switch event {
        case .knob(let steps): menuChoice = steps < 0 ? .record : .lookback
        case .left: menuChoice = .record
        case .right: menuChoice = .lookback
        case .confirm: chooseMenu(menuChoice)
        case .cancel: go(to: .home)
        case .record: chooseMenu(.record)
        default: break
        }
    }

    private func handleAddMember(_ event: ControlEvent) {
        guard !confirmFlash else { return }
        switch event {
        case .knob(let steps): moveLetter(by: steps)
        case .left: moveLetter(by: -1)
        case .right: moveLetter(by: 1)
        case .confirm: pressLetterKey()
        case .cancel: go(to: .home)
        default: break
        }
    }

    /// Confirm on the wall: the check turns green, then the choice opens.
    private func confirmThen(_ action: @escaping @MainActor () -> Void) {
        guard !confirmFlash else { return }
        confirmCount += 1
        confirmFlash = true
        timer?.cancel()
        timer = scheduler.after(Self.confirmSeconds) { [weak self] in
            guard let self else { return }
            confirmFlash = false
            action()
        }
    }

    private func handleFilm(_ event: ControlEvent, _ state: FilmState) {
        switch (state, event) {
        case (.ready, .confirm), (.ready, .record):
            startCountdown()
        case (.ready, .cancel):
            menuChoice = .record
            go(to: .memberMenu)
        case (.countdown, .cancel), (.countdown, .record):
            // Stopping before filming started leaves nothing to keep.
            go(to: .makeFilm(.ready))
        case (.filming, .cancel):
            go(to: .makeFilm(.ready))
        case (.filming, .record):
            finishFilming()
        default:
            break
        }
    }

    private func handleHeight(_ event: ControlEvent, _ state: HeightState) {
        switch (state, event) {
        case (.cuttingOut, .cancel):
            go(to: .makeFilm(.ready))
        case (.editing, .knob(let steps)):
            adjustDraft(by: steps, coarse: false)
        case (.editing, .left):
            adjustDraft(by: -1, coarse: true)
        case (.editing, .right):
            adjustDraft(by: 1, coarse: true)
        case (.editing, .confirm):
            saveRecord()
        case (.editing, .cancel), (.noPerson, .cancel), (.noPerson, .confirm):
            go(to: .makeFilm(.ready))
        default:
            break
        }
    }

    private func handleManual(_ event: ControlEvent) {
        switch event {
        case .knob(let steps): moveRecord(by: steps)
        case .left: moveRecord(by: -1)
        case .right: moveRecord(by: 1)
        case .confirm: replayCount += 1
        case .cancel:
            menuChoice = .lookback
            go(to: .memberMenu)
        case .autoPlayToggle: startAutoPlay()
        // 녹화는 Make 모드에서만 — 모드 스위치와 화면이 어긋나지 않게
        case .record, .mode: break
        }
    }

    /// Any control stops auto play; knob and Left / Right then also move.
    private func handleAutoPlay(_ event: ControlEvent) {
        stopAutoPlay()
        switch event {
        case .knob(let steps): moveRecord(by: steps)
        case .left: moveRecord(by: -1)
        case .right: moveRecord(by: 1)
        default: break
        }
    }

    private func handleFit(_ event: ControlEvent) {
        switch event {
        case .knob(let steps): nudgeFit(by: steps)
        case .left: selectFitValue(by: -1)
        case .right: selectFitValue(by: 1)
        case .confirm, .cancel: finishFit()
        default: break
        }
    }

    // MARK: Navigation

    func go(to next: Route) {
        let previous = route
        timer?.cancel()
        timer = nil

        if previous.holdsMakeSession && !next.holdsMakeSession {
            let hadClip = discardMakeSession(wasFilming: { if case .makeFilm(.filming) = previous { return true }; return false }())
            if hadClip && next.mode != .make { showNotice(L("Not saved")) }
        }
        if previous == .memoryWall && next != .memoryWall {
            isAutoPlaying = false
        }
        let onWall: (Route) -> Bool = { if case .record = $0 { return true }; return $0 == .memoryWall }
        if onWall(previous) && !onWall(next) { wallPlayer.stop() }

        if next == .home {
            highlight = memberID.flatMap { id in store.members.firstIndex { $0.id == id } }
                ?? min(highlight, store.members.count)
        }

        if next.usesCamera && !previous.usesCamera { camera.startPreview() }
        if previous.usesCamera && !next.usesCamera { camera.stopPreview() }

        route = next
        if let nextMode = next.mode { mode = nextMode }
        updateLight()
    }

    // MARK: Home (H) and the member menu (H1)

    func moveHighlight(by steps: Int) {
        highlight = min(max(highlight + steps, 0), homeCardCount - 1)
    }

    /// Tapping a card on the phone: bring it to the middle, then open it.
    func openTile(_ index: Int) {
        guard (0..<homeCardCount).contains(index) else { return }
        highlight = index
        openHighlighted()
    }

    private func openHighlighted() {
        if highlightsAddCard {
            confirmThen { [weak self] in self?.openAddMember() }
            return
        }
        guard let member = highlightedMember else { return }
        confirmThen { [weak self] in
            guard let self else { return }
            memberID = member.id
            menuChoice = .record
            go(to: .memberMenu)
        }
    }

    /// Record or Lookback for the chosen member (Confirm, or a tap on the phone).
    func chooseMenu(_ action: MemberAction) {
        guard route == .memberMenu, currentMember != nil else { return }
        menuChoice = action
        confirmThen { [weak self] in
            guard let self else { return }
            switch action {
            case .record:
                go(to: .makeFilm(.ready))
            case .lookback:
                recordIndex = max(0, currentRecords.count - 1)
                go(to: .memoryWall)
                if settings.autoPlay { startAutoPlay() }
            }
        }
    }

    /// The phone's way of moving the menu highlight without confirming.
    func highlightMenu(_ action: MemberAction) {
        guard route == .memberMenu else { return }
        menuChoice = action
    }

    func closeMemberMenu() {
        guard route == .memberMenu else { return }
        go(to: .home)
    }

    // MARK: Add member (A2)

    func openAddMember() {
        nameDraft = ""
        letterIndex = LetterKey.startIndex
        go(to: .addMember)
    }

    func moveLetter(by steps: Int) {
        letterIndex += steps
    }

    /// Confirm on the letter wheel: add the letter, remove the last one, or save.
    func pressLetterKey() {
        guard route == .addMember else { return }
        confirmCount += 1
        switch LetterKey.at(letterIndex) {
        case .letter(let character):
            if nameDraft.count < Self.maxNameLength { nameDraft.append(character) }
        case .delete:
            if !nameDraft.isEmpty { nameDraft.removeLast() }
        case .save:
            saveNewMember()
        }
    }

    /// Tapping a key on the phone: bring it to the middle and press it.
    func tapLetterKey(at index: Int) {
        letterIndex = index
        pressLetterKey()
    }

    private func saveNewMember() {
        let name = nameDraft.capitalized
        guard !name.isEmpty else { return }
        confirmCount -= 1   // confirmThen counts this press
        confirmThen { [weak self] in
            guard let self else { return }
            if let member = store.addMember(name: name) { memberID = member.id }
            nameDraft = ""
            go(to: .home)
        }
    }

    // MARK: Film (M2)

    private func startCountdown() {
        countdownTick(Self.countdownSeconds)
    }

    private func countdownTick(_ remaining: Int) {
        if remaining == 0 {
            startFilming()
            return
        }
        go(to: .makeFilm(.countdown(remaining)))
        timer = scheduler.after(1) { [weak self] in self?.countdownTick(remaining - 1) }
    }

    private func startFilming() {
        camera.startRecording(sound: settings.soundOn)
        filmingTick(Self.filmSeconds)
    }

    private func filmingTick(_ secondsLeft: Int) {
        if secondsLeft == 0 {
            finishFilming()
            return
        }
        go(to: .makeFilm(.filming(secondsLeft: secondsLeft)))
        timer = scheduler.after(1) { [weak self] in self?.filmingTick(secondsLeft - 1) }
    }

    private func finishFilming() {
        go(to: .makeHeight(.cuttingOut(progress: 0)))
        camera.stopRecording { [weak self] movie in
            guard let self, case .makeHeight(.cuttingOut) = route else {
                if let movie { try? FileManager.default.removeItem(at: movie) }
                return
            }
            startProcessing(movie)
        }
    }

    private func startProcessing(_ movie: URL?) {
        let camera = settings.camera
        let processor = processor
        processingTask = Task { [weak self] in
            let clip: ProcessedClip?
            do {
                clip = try await processor.process(movie: movie, camera: camera) { progress in
                    guard let self, case .makeHeight(.cuttingOut) = self.route else { return }
                    self.go(to: .makeHeight(.cuttingOut(progress: progress)))
                }
            } catch {
                clip = nil
            }
            if let movie { Self.discardMovie(movie) }
            guard !Task.isCancelled else { return }
            self?.finishProcessing(clip)
        }
    }

    /// The raw movie is not kept. Debug builds keep the last one as tmp/last-film.mov, to check
    /// filming on a device (copy it off with Xcode's Devices window).
    nonisolated static func discardMovie(_ movie: URL) {
        #if DEBUG
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("last-film.mov")
        try? FileManager.default.removeItem(at: keep)
        try? FileManager.default.moveItem(at: movie, to: keep)
        #else
        try? FileManager.default.removeItem(at: movie)
        #endif
    }

    /// Called when the cut-out is done. Nil means nobody was found in the video.
    func finishProcessing(_ clip: ProcessedClip?) {
        processingTask = nil
        guard case .makeHeight(.cuttingOut) = route else { return }
        guard let clip else {
            go(to: .makeHeight(.noPerson))
            return
        }
        let start = HeightEstimator.initialDraft(estimateMM: clip.estimatedMM,
                                                 lastMM: memberID.flatMap(store.lastRecord)?.heightMM)
        draft = MakeDraft(clip: clip, heightMM: start.mm, fromEstimate: start.fromEstimate)
        go(to: .makeHeight(clip.personFound ? .editing : .noPerson))
    }

    /// "Nobody found": keep the clip as filmed anyway (testing without a person in front of the wall).
    func useClipWithoutPerson() {
        guard route == .makeHeight(.noPerson), draft != nil else { return }
        go(to: .makeHeight(.editing))
    }

    /// Stops filming or cutting out and deletes unsaved files. Returns whether a clip was lost.
    private func discardMakeSession(wasFilming: Bool) -> Bool {
        var hadClip = wasFilming
        if wasFilming {
            camera.stopRecording { movie in
                if let movie { try? FileManager.default.removeItem(at: movie) }
            }
        }
        if let processingTask {
            processingTask.cancel()
            self.processingTask = nil
            hadClip = true
        }
        if let clip = draft?.clip {
            for url in [clip.videoURL, clip.posterURL, clip.rawVideoURL].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: url)
            }
            hadClip = true
        }
        draft = nil
        return hadClip
    }

    // MARK: Height (M3)

    private func adjustDraft(by steps: Int, coarse: Bool) {
        guard var draft else { return }
        let base = draft.heightMM ?? HeightFormatter.emptyFieldStartMM
        draft.heightMM = HeightFormatter.step(base, by: steps, unit: settings.unit, coarse: coarse)
        draft.fromEstimate = false
        self.draft = draft
    }

    private func saveRecord() {
        guard let memberID, let draft, let mm = draft.heightMM, HeightFormatter.isValid(mm) else { return }
        let record = store.addRecord(memberID: memberID, heightMM: mm,
                                     source: draft.fromEstimate ? .estimated : .edited,
                                     clip: draft.clip)
        // 파일은 Store로 옮겨졌으니 discard 대상이 아님
        self.draft = nil
        recordIndex = currentRecords.firstIndex { $0.id == record.id } ?? max(0, currentRecords.count - 1)
        go(to: .memoryWall)
        replayCount += 1
        light.recording = .saved
        controller.setLight(light)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Memory wall (R2)

    func moveRecord(by steps: Int) {
        let count = currentRecords.count
        guard count > 0 else { return }
        let next = min(max(recordIndex + steps, 0), count - 1)
        if next != recordIndex {
            recordIndex = next
            replayCount += 1
        }
    }

    /// Selecting a mark on the phone's wall copy.
    func selectRecord(_ index: Int) {
        guard currentRecords.indices.contains(index) else { return }
        if isAutoPlaying { stopAutoPlay() }
        recordIndex = index
        replayCount += 1
    }

    private func startAutoPlay() {
        guard !currentRecords.isEmpty else { return }
        isAutoPlaying = true
        settings.autoPlay = true
        recordIndex = 0
        replayCount += 1
        scheduleAutoPlayStep()
    }

    private func scheduleAutoPlayStep() {
        guard let record = selectedRecord else { return }
        timer = scheduler.after(clipSeconds(record)) { [weak self] in
            guard let self, isAutoPlaying else { return }
            recordIndex = (recordIndex + 1) % max(1, currentRecords.count)
            replayCount += 1
            scheduleAutoPlayStep()
        }
    }

    private func stopAutoPlay() {
        timer?.cancel()
        timer = nil
        isAutoPlaying = false
        settings.autoPlay = false
    }

    /// How long auto play shows a record: its clip's length, or a short still for sample records.
    private func clipSeconds(_ record: GrowthRecord) -> Double {
        if let duration = record.duration, duration > 0 { return duration }
        return record.videoFile == nil && record.rawVideoFile == nil ? Self.stillSeconds : Double(Self.filmSeconds)
    }

    /// The clip file for a record: the cut-out, or the clip as filmed with Show background.
    func clipURL(_ record: GrowthRecord) -> URL? {
        let file = settings.showBackground ? (record.rawVideoFile ?? record.videoFile)
                                           : (record.videoFile ?? record.rawVideoFile)
        return store.mediaURL(file)
    }

    func setShowBackground(_ on: Bool) {
        settings.showBackground = on
        replayCount += 1
    }

    private func playSelectedClip() {
        let onWall: Bool = { if case .record = route { return true }; return route == .memoryWall }()
        guard onWall, let record = selectedRecord else { return }
        wallPlayer.play(clipURL(record), sound: settings.soundOn && record.hasSound)
    }

    // MARK: One record (R3)

    func openRecord(_ id: UUID) {
        guard store.record(id) != nil else { return }
        if isAutoPlaying { stopAutoPlay() }
        go(to: .record(id))
    }

    func changeHeight(of id: UUID, to mm: Int) {
        store.updateHeight(of: id, heightMM: HeightFormatter.clamp(mm))
    }

    /// R3: - and + on one record's height, in the unit's steps.
    func stepHeight(of id: UUID, by steps: Int, coarse: Bool) {
        guard let record = store.record(id) else { return }
        changeHeight(of: id, to: HeightFormatter.step(record.heightMM, by: steps, unit: settings.unit, coarse: coarse))
    }

    /// R3: a record's date. Records are ordered by date, so the selection follows the record.
    func changeDate(of id: UUID, to date: Date) {
        store.updateDate(of: id, to: min(date, .now))
        if let index = currentRecords.firstIndex(where: { $0.id == id }) { recordIndex = index }
    }

    func deleteRecord(_ id: UUID) {
        store.deleteRecord(id)
        recordIndex = min(recordIndex, max(0, currentRecords.count - 1))
        go(to: .memoryWall)
        replayCount += 1
    }

    // MARK: Members (A1)

    func openMemberEdit(_ id: UUID?) {
        if case .memberEdit = route {} else { memberEditReturn = route }
        go(to: .memberEdit(id))
    }

    func saveMember(id: UUID?, name: String, colorIndex: Int, photo: PhotoChange = .keep) {
        var savedID: UUID?
        if let id, var member = store.member(id) {
            member.name = name
            member.colorIndex = colorIndex
            store.updateMember(member)
            savedID = id
        } else if let member = store.addMember(name: name, colorIndex: colorIndex) {
            memberID = member.id
            savedID = member.id
        }
        if let savedID, photo != .keep { store.setPhoto(photo, for: savedID) }
        closeMemberEdit()
    }

    func deleteMember(_ id: UUID) {
        store.deleteMember(id)
        if memberID == id { memberID = nil }
        closeMemberEdit()
    }

    func closeMemberEdit() {
        go(to: validated(memberEditReturn))
    }

    // MARK: Settings

    func openSettings() {
        switch route {
        case .settings, .wizard, .memberEdit: break
        default: settingsReturn = route
        }
        go(to: .settings(.list))
    }

    func openSettingsPage(_ page: SettingsPage) {
        if page == .fitToWall { fitValue = .floor }
        go(to: .settings(page))
    }

    func leaveSettings() {
        go(to: validated(settingsReturn))
    }

    func deleteEverything() {
        store.deleteAll()
        memberID = nil
        recordIndex = 0
    }

    func loadSampleFamily() {
        store.loadSampleFamily()
        memberID = nil
        recordIndex = 0
    }

    /// A route to return to may point at something deleted meanwhile, or at a make session
    /// that was discarded on the way out.
    private func validated(_ target: Route) -> Route {
        switch target {
        case .makeFilm, .makeHeight:
            return currentMember == nil ? .home : .makeFilm(.ready)
        case .memoryWall, .memberMenu:
            return currentMember == nil ? .home : target
        case .record(let id):
            return store.record(id) == nil ? (currentMember == nil ? .home : .memoryWall) : target
        case .memberEdit(let id?):
            return store.member(id) == nil ? .settings(.family) : target
        default:
            return target
        }
    }

    /// Starts Bluetooth, which asks for permission the first time (permissions page).
    func startController() {
        controller.start()
    }

    /// Tapping the controller chip: the permissions page when Bluetooth is not allowed,
    /// otherwise the controller page.
    func openControllerHelp() {
        openSettings()
        openSettingsPage(controllerStatus == .notAllowed ? .permissions : .controller)
    }

    func clearControlLog() {
        controlLog = []
        lastControl = nil
    }

    /// Light test on the controller page. The next screen change writes the real state again.
    func testLight(_ recording: LightState.Recording) {
        var test = light
        test.recording = recording
        controller.setLight(test)
    }

    func forgetController() {
        controller.forget()
    }

    // MARK: Fit to wall (S2)

    func selectFitValue(_ value: FitValue) { fitValue = value }

    // MARK: Camera position (S3)

    func saveCameraPosition(_ position: CameraPosition) {
        settings.camera = position
    }

    /// The foot guide for M2 and the wall.
    var footGuide: FootGuide {
        FootGuide.make(camera: settings.camera,
                       outlineMM: FootGuide.outlineMM(lastMM: memberID.flatMap(store.lastRecord)?.heightMM))
    }

    private func selectFitValue(by step: Int) {
        let all = FitValue.allCases
        fitValue = all[min(max(fitValue.rawValue + step, 0), all.count - 1)]
    }

    func nudgeFit(by steps: Int) {
        let n = Double(steps)
        switch fitValue {
        case .floor: settings.wall.floorPt = max(0, settings.wall.floorPt + n * (fitFine ? 1 : 5))
        case .size: settings.wall.ptPerCM = min(max(settings.wall.ptPerCM + n * (fitFine ? 0.01 : 0.05), 1), 20)
        case .shift: settings.wall.shiftPt += n * (fitFine ? 1 : 5)
        }
    }

    private func finishFit() {
        if case .wizard = route { wizardNext() } else { go(to: .settings(.list)) }
    }

    // MARK: Wizard (W)

    /// From the "Finish setup" banner: straight to the setup steps.
    func startWizard() {
        go(to: .wizard(.permissions))
    }

    /// "Set up later" on the welcome pages: setup stays reachable from the banner and Settings.
    func skipWizard() {
        settings.wizardDone = true
        go(to: .home)
    }

    /// Next and Skip both move on; every step can be reopened from Settings.
    func wizardNext() {
        guard case .wizard(let step) = route else { return }
        if let next = WizardStep(rawValue: step.rawValue + 1) {
            if next == .fitToWall { fitValue = .floor }
            go(to: .wizard(next))
        } else {
            settings.wizardDone = true
            go(to: .home)
        }
    }

    // MARK: Controller light and notices

    private func updateLight() {
        var next = light
        switch route {
        case .makeFilm(.countdown): next.recording = .countdown
        case .makeFilm(.filming), .makeHeight(.cuttingOut): next.recording = .steady
        default: next.recording = .off
        }
        next.mode = mode ?? .memory
        guard next != light else { return }
        light = next
        controller.setLight(next)
    }

    private func showNotice(_ text: String) {
        notice = text
        noticeTimer?.cancel()
        noticeTimer = scheduler.after(2) { [weak self] in self?.notice = nil }
    }
}
