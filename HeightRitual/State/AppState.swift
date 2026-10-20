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
    /// Goes up on every control used, so the onboarding's controller drawing can show the press.
    private(set) var inputCount = 0
    /// Onboarding: the member it added, the height on its dial, seconds left while "filming".
    private(set) var tutorialMemberID: UUID?
    private(set) var tutorialMM = 1200
    private(set) var tutorialFilmLeft: Int?
    /// Controls used at least once in the onboarding: filled with colour on its drawing.
    private(set) var tutorialLearned: Set<TutorialLesson> = []
    /// The lesson just learned, shown as a little toast for a moment.
    private(set) var tutorialToast: TutorialLesson?
    @ObservationIgnored private var toastTimer: ScheduledTask?
    /// The record just saved, for the "Saved" screen.
    private(set) var savedRecordID: UUID?
    /// "Turn the knob or press ◀ ▶ to look back" on the wall, until the first move.
    private(set) var showsLookbackHint = false
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
    /// The tile the controller has chosen on the projector's settings grid.
    private(set) var settingsHighlight: SettingsTile = .setupGuide
    /// The option the controller has chosen on the projector's Units page.
    private(set) var unitHighlight: HeightUnit = .cm
    /// The point colour the controller has chosen on the projector's page: nil is Black.
    private(set) var accentHighlight: Int?
    /// The member the controller has chosen on the projector's Family page.
    private(set) var familyHighlight = 0
    /// On the projector's Sound page: true is On.
    private(set) var soundHighlight = false
    /// A member opened from the projector's Family page.
    private(set) var memberStep: MemberStep = .choices
    /// On that member's page: 0 Change colour, 1 Delete member.
    private(set) var memberChoice = 0
    private(set) var memberColourHighlight = 0
    /// On a question (sample family, delete everything, delete member): true is the action, false
    /// Cancel, which is chosen first.
    private(set) var confirmChoice = false
    /// Delete everything asks twice: 1, then 2.
    private(set) var deleteStep = 1

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

    /// Cards on the Home wheel: every member, then the Add card. Settings opens with Back on Home.
    var homeCardCount: Int { store.members.count + 1 }

    /// The highlighted Home card is the Add card.
    var highlightsAddCard: Bool { highlight == store.members.count }

    /// Back on Home opens Settings, but not right after arriving on Home: someone pressing Back
    /// a few times to get home should not land in Settings.
    private(set) var homeBackReady = true
    @ObservationIgnored private var homeBackTimer: ScheduledTask?
    static let homeBackDelay = 1.0

    /// The member on the highlighted Home card.
    var highlightedMember: Member? {
        store.members.indices.contains(highlight) ? store.members[highlight] : nil
    }

    var showsEstimateNote: Bool { draft?.fromEstimate == true }

    // MARK: Input

    func handle(_ event: ControlEvent) {
        let previous = lastControl
        lastControl = event
        inputCount += 1
        // 컨트롤러 테스트 페이지: 신호는 기록만 하고 화면은 그대로 둔다
        // On the projector the test page is left with Back twice in a row.
        if route == .settings(.controller) {
            if event == .cancel, previous == .cancel { go(to: .settings(.list)) }
            return
        }
        if case .mode(let next) = event {
            switchMode(to: next)
            return
        }
        switch route {
        case .home:
            handleHome(event)
        case .memberMenu:
            handleMenu(event)
        case .makeSaved:
            handleSaved(event)
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
        case .memberEdit(let id?) where memberEditInSettings:
            handleMember(event, id)
        case .memberEdit:
            if event == .cancel { closeMemberEdit() }
        case .settings(.fitToWall), .wizard(.fitToWall):
            handleFit(event)
        case .settings(.list):
            handleSettingsGrid(event)
        case .settings(.units):
            handleUnits(event)
        case .settings(.pointColour):
            handlePointColour(event)
        case .settings(.family):
            handleFamily(event)
        case .settings(.sound):
            handleSound(event)
        case .settings(.confirmSample), .settings(.confirmDelete):
            handleQuestion(event)
        case .settings(let page):
            if event == .cancel { page == .list ? leaveSettings() : go(to: .settings(.list)) }
        case .wizard:
            break
        case .tutorial(let step):
            handleTutorial(event, step)
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
        case .cancel: if homeBackReady { openSettings() }
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
            startFilming()
        case (.ready, .cancel):
            menuChoice = .record
            go(to: .memberMenu)
        case (.filming, .cancel):
            go(to: .makeFilm(.ready))
        case (.filming, .record), (.filming, .confirm):
            // Confirm (the round button) stops early; the box has no Record button any more.
            finishFilming()
        default:
            break
        }
    }

    private func handleSaved(_ event: ControlEvent) {
        guard !confirmFlash else { return }
        switch event {
        case .confirm: seeGrowth()
        case .cancel: measureSomeoneElse()
        default: break
        }
    }

    private func handleHeight(_ event: ControlEvent, _ state: HeightState) {
        switch (state, event) {
        case (.cuttingOut, .cancel):
            go(to: .makeFilm(.ready))
        case (.editing, .knob(let steps)):
            adjustDraft(by: steps, coarse: false, fineMM: 1)
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
        if next == .memoryWall && previous != .memoryWall {
            if case .record = previous {} else { showsLookbackHint = true }
        }
        let onWall: (Route) -> Bool = { if case .record = $0 { return true }; return $0 == .memoryWall }
        if onWall(previous) && !onWall(next) { wallPlayer.stop() }

        if next == .home && previous != .home {
            homeBackReady = false
            homeBackTimer?.cancel()
            homeBackTimer = scheduler.after(Self.homeBackDelay) { [weak self] in self?.homeBackReady = true }
        }
        if next == .home {
            highlight = memberID.flatMap { id in store.members.firstIndex { $0.id == id } }
                ?? min(highlight, store.members.count)
        }

        if next.usesCamera && !previous.usesCamera { camera.startPreview(askMicrophone: settings.soundOn) }
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
                // Opens on the newest record, its clip playing at once.
                recordIndex = max(0, currentRecords.count - 1)
                go(to: .memoryWall)
                if settings.autoPlay { startAutoPlay() } else { replayCount += 1 }
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

    /// Record starts filming at once (no countdown); the screens show the time left.
    func startFilming() {
        guard route == .makeFilm(.ready) else { return }
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
        #if DEBUG
        // Simulator (no camera): `-DebugFakeClip` pretends a person 120 cm tall was filmed, so the
        // height and saved screens can be checked.
        if movie == nil, ProcessInfo.processInfo.arguments.contains("-DebugFakeClip") {
            finishProcessing(ProcessedClip(estimatedMM: 1200))
            return
        }
        #endif
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

    private func adjustDraft(by steps: Int, coarse: Bool, fineMM: Int = 5) {
        guard var draft else { return }
        if !settings.heightStepsLearned { settings.heightStepsLearned = true }
        let base = draft.heightMM ?? HeightFormatter.emptyFieldStartMM
        draft.heightMM = HeightFormatter.step(base, by: steps, unit: settings.unit, coarse: coarse, fineMM: fineMM)
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
        savedRecordID = record.id
        go(to: .makeSaved)
        light.recording = .saved
        controller.setLight(light)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Saved (M4)

    var savedRecord: GrowthRecord? { savedRecordID.flatMap(store.record) }

    /// "See Nora's growth": the memory wall on the record just saved.
    func seeGrowth() {
        guard route == .makeSaved else { return }
        confirmThen { [weak self] in
            guard let self else { return }
            if let id = savedRecordID, let index = currentRecords.firstIndex(where: { $0.id == id }) {
                recordIndex = index
            }
            go(to: .memoryWall)
            replayCount += 1
        }
    }

    /// "Return to home": back to the wheel.
    func measureSomeoneElse() {
        guard route == .makeSaved else { return }
        go(to: .home)
    }

    /// Phone: dragging the dial sets the height directly.
    func setDraftHeight(_ mm: Int) {
        guard var draft, route == .makeHeight(.editing) else { return }
        let clamped = min(max(mm, HeightFormatter.minMM), HeightFormatter.maxMM)
        guard clamped != draft.heightMM else { return }
        draft.heightMM = clamped
        draft.fromEstimate = false
        self.draft = draft
    }

    // MARK: Memory wall (R2)

    func moveRecord(by steps: Int) {
        showsLookbackHint = false
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
        let url = clipURL(record)
        // A cut-out has no sound track; its sound comes from the clip as filmed.
        let raw = store.mediaURL(record.rawVideoFile)
        wallPlayer.play(url, sound: settings.soundOn && record.hasSound, soundFrom: url == raw ? nil : raw)
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
        memberStep = .choices
        memberChoice = 0
        go(to: .memberEdit(id))
    }

    func saveMember(id: UUID?, name: String, colorIndex: Int, cardStyle: CardStyle? = nil,
                    photo: PhotoChange = .keep) {
        var savedID: UUID?
        if let id, var member = store.member(id) {
            member.name = name
            member.colorIndex = colorIndex
            if let cardStyle { member.cardStyle = cardStyle }
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
        settingsHighlight = .setupGuide
        go(to: .settings(.list))
    }

    func openSettingsPage(_ page: SettingsPage) {
        if page == .fitToWall { fitValue = .floor }
        if page == .units { unitHighlight = settings.unit }
        if page == .pointColour { accentHighlight = settings.accentIndex }
        if page == .sound { soundHighlight = settings.soundOn }
        if page == .family, route == .settings(.list) { familyHighlight = 0 }
        if page == .confirmSample || page == .confirmDelete {
            confirmChoice = false
            deleteStep = 1
        }
        go(to: .settings(page))
    }

    /// The projector's settings grid: the knob, Left and Right move through the tiles; Select opens
    /// a tile that has a projector page; Back closes Settings.
    private func handleSettingsGrid(_ event: ControlEvent) {
        switch event {
        case .knob(let steps): moveSettingsHighlight(by: steps)
        case .left: moveSettingsHighlight(by: -1)
        case .right: moveSettingsHighlight(by: 1)
        case .confirm: openSettingsPage(settingsHighlight.page)
        case .cancel: leaveSettings()
        default: break
        }
    }

    private func moveSettingsHighlight(by steps: Int) {
        let all = SettingsTile.allCases
        settingsHighlight = all[min(max(settingsHighlight.rawValue + steps, 0), all.count - 1)]
    }

    /// The projector's Units page: the knob, Left and Right choose; Select saves and goes back.
    private func handleUnits(_ event: ControlEvent) {
        switch event {
        case .knob(let steps) where steps < 0: unitHighlight = .cm
        case .knob: unitHighlight = .ftin
        case .left: unitHighlight = .cm
        case .right: unitHighlight = .ftin
        case .confirm: chooseUnit(unitHighlight)
        case .cancel: go(to: .settings(.list))
        default: break
        }
    }

    // MARK: Settings questions on the projector and the phone

    /// Load sample family or Delete everything: Left / the knob back is Cancel, Right / forward the
    /// action; Select answers; Back cancels.
    private func handleQuestion(_ event: ControlEvent) {
        switch event {
        case .knob(let steps): confirmChoice = steps > 0
        case .left: confirmChoice = false
        case .right: confirmChoice = true
        case .confirm: answerQuestion(confirmChoice)
        case .cancel: go(to: .settings(.list))
        default: break
        }
    }

    /// The answer, from Select on the projector or a button on the phone. Delete everything asks a
    /// second time before it deletes.
    func answerQuestion(_ yes: Bool) {
        guard yes else { go(to: .settings(.list)); return }
        switch route {
        case .settings(.confirmSample):
            loadSampleFamily()
            go(to: .settings(.list))
            showNotice("Sample family loaded")
        case .settings(.confirmDelete) where deleteStep == 1:
            deleteStep = 2
            confirmChoice = false
        case .settings(.confirmDelete):
            deleteEverything()
            go(to: .settings(.list))
            showNotice("Everything deleted")
        default:
            break
        }
    }

    // MARK: Family on the projector

    /// The members; Select opens a member's page. Adding a member is done from Home.
    private func handleFamily(_ event: ControlEvent) {
        let count = store.members.count
        func move(_ steps: Int) { familyHighlight = min(max(familyHighlight + steps, 0), max(count - 1, 0)) }
        switch event {
        case .knob(let steps): move(steps)
        case .left: move(-1)
        case .right: move(1)
        case .confirm:
            if familyHighlight < count { openMemberEdit(store.members[familyHighlight].id) }
        case .cancel: go(to: .settings(.list))
        default: break
        }
    }

    /// A member from the projector's Family page: Change colour or Delete member. Renaming needs
    /// typing, so it stays on the phone.
    private func handleMember(_ event: ControlEvent, _ id: UUID) {
        guard let member = store.member(id) else { closeMemberEdit(); return }
        let colours = Palette.memberColors.count
        switch (memberStep, event) {
        case (.choices, .knob(let steps)): memberChoice = steps > 0 ? 1 : 0
        case (.choices, .left): memberChoice = 0
        case (.choices, .right): memberChoice = 1
        case (.choices, .confirm):
            if memberChoice == 0 {
                memberColourHighlight = member.colorIndex % colours
                memberStep = .colour
            } else {
                confirmChoice = false
                memberStep = .confirmDelete
            }
        case (.choices, .cancel): closeMemberEdit()

        case (.colour, .knob(let steps)):
            memberColourHighlight = min(max(memberColourHighlight + steps, 0), colours - 1)
        case (.colour, .left): memberColourHighlight = max(memberColourHighlight - 1, 0)
        case (.colour, .right): memberColourHighlight = min(memberColourHighlight + 1, colours - 1)
        case (.colour, .confirm):
            var changed = member
            changed.colorIndex = memberColourHighlight
            store.updateMember(changed)
            memberStep = .choices
        case (.colour, .cancel): memberStep = .choices

        case (.confirmDelete, .knob(let steps)): confirmChoice = steps > 0
        case (.confirmDelete, .left): confirmChoice = false
        case (.confirmDelete, .right): confirmChoice = true
        case (.confirmDelete, .confirm):
            if confirmChoice {
                memberStep = .choices
                deleteMember(id)
            } else {
                memberStep = .choices
            }
        case (.confirmDelete, .cancel): memberStep = .choices
        default: break
        }
    }

    /// The projector's Sound page: On first, then Off. The knob, Left and Right choose; Select saves
    /// and goes back.
    private func handleSound(_ event: ControlEvent) {
        switch event {
        case .knob(let steps): soundHighlight = steps < 0
        case .left: soundHighlight = true
        case .right: soundHighlight = false
        case .confirm: chooseSound(soundHighlight)
        case .cancel: go(to: .settings(.list))
        default: break
        }
    }

    /// Saves sound on or off and goes back to the settings list, from the phone or the controller.
    func chooseSound(_ on: Bool) {
        settings.soundOn = on
        soundHighlight = on
        if route == .settings(.sound) { go(to: .settings(.list)) }
    }

    /// Black, then each palette colour, in the order the pages list them.
    static let pointColours: [Int?] = [nil] + Palette.memberColors.indices.map { $0 }

    /// The projector's Point colour page: the knob, Left and Right move through Black and the
    /// colours; Select saves and goes back.
    private func handlePointColour(_ event: ControlEvent) {
        let all = Self.pointColours
        let index = all.firstIndex(of: accentHighlight) ?? 0
        switch event {
        case .knob(let steps): accentHighlight = all[min(max(index + steps, 0), all.count - 1)]
        case .left: accentHighlight = all[max(index - 1, 0)]
        case .right: accentHighlight = all[min(index + 1, all.count - 1)]
        case .confirm: choosePointColour(accentHighlight)
        case .cancel: go(to: .settings(.list))
        default: break
        }
    }

    /// Saves the point colour and goes back to the settings list, from the phone or the controller.
    func choosePointColour(_ index: Int?) {
        settings.accentIndex = index
        accentHighlight = index
        if route == .settings(.pointColour) { go(to: .settings(.list)) }
    }

    /// Saves the unit and goes back to the settings list, from the phone or the controller.
    func chooseUnit(_ unit: HeightUnit) {
        settings.unit = unit
        unitHighlight = unit
        if route == .settings(.units) { go(to: .settings(.list)) }
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
        }
    }

    private func finishFit() {
        if case .wizard = route { wizardNext() } else { go(to: .settings(.list)) }
    }

    // MARK: Onboarding with the controller (T)

    /// Settings > Onboarding with controller.
    func startTutorial() {
        tutorialLearned = []
        tutorialToast = nil
        tutorialMemberID = nil
        tutorialFilmLeft = nil
        go(to: .tutorial(.welcome))
    }

    /// The phone's close button: leave the onboarding where it is.
    func endTutorial() {
        timer?.cancel()
        tutorialFilmLeft = nil
        if let tutorialMemberID { memberID = tutorialMemberID }
        go(to: .home)
    }

    private func tutorialGo(_ step: TutorialStep) {
        go(to: .tutorial(step))
    }

    private func handleTutorial(_ event: ControlEvent, _ step: TutorialStep) {
        guard !confirmFlash else { return }
        learn(event, on: step)
        if event == .cancel {
            // Back is a step back everywhere, which is also what the "Saved" step teaches.
            if step == .saved {
                menuChoice = .record
                tutorialGo(.chooseLookback)
            } else if step == .film && tutorialFilmLeft != nil {
                timer?.cancel()
                tutorialFilmLeft = nil
            } else if let previous = step.previous {
                if previous == .name, let id = tutorialMemberID {
                    // Back to the name: the member it made goes again, so Save does not add a second.
                    store.deleteMember(id)
                    tutorialMemberID = nil
                    memberID = nil
                }
                if previous == .name {
                    nameDraft = ""
                    letterIndex = LetterKey.startIndex
                }
                tutorialGo(previous)
            } else {
                endTutorial()
            }
            return
        }
        switch step {
        case .welcome:
            if event == .confirm { confirmThen { [weak self] in self?.tutorialGo(.family) } }
        case .family:
            if event == .confirm {
                confirmThen { [weak self] in
                    guard let self else { return }
                    nameDraft = ""
                    letterIndex = LetterKey.startIndex
                    tutorialGo(.name)
                }
            }
        case .name:
            switch event {
            case .knob(let steps): moveLetter(by: steps)
            case .left: moveLetter(by: -1)
            case .right: moveLetter(by: 1)
            case .confirm: pressTutorialKey()
            default: break
            }
        case .chooseRecord, .chooseLookback:
            switch event {
            case .knob(let steps): menuChoice = steps < 0 ? .record : .lookback
            case .left: menuChoice = .record
            case .right: menuChoice = .lookback
            case .confirm:
                let wanted: MemberAction = step == .chooseRecord ? .record : .lookback
                guard menuChoice == wanted else {
                    showNotice(wanted == .record ? L("Choose Record to measure first") : L("Choose Lookback to see the record"))
                    return
                }
                confirmThen { [weak self] in
                    guard let self else { return }
                    if step == .chooseRecord {
                        tutorialGo(.film)
                    } else {
                        recordIndex = max(0, currentRecords.count - 1)
                        tutorialGo(.lookback)
                    }
                }
            default: break
            }
        case .film:
            if event == .confirm && tutorialFilmLeft == nil { tutorialFilmTick(Self.filmSeconds) }
        case .height:
            switch event {
            case .knob(let steps): tutorialMM = HeightFormatter.step(tutorialMM, by: steps, unit: settings.unit, coarse: false, fineMM: 1)
            case .left: tutorialMM = HeightFormatter.step(tutorialMM, by: -1, unit: settings.unit, coarse: true)
            case .right: tutorialMM = HeightFormatter.step(tutorialMM, by: 1, unit: settings.unit, coarse: true)
            case .confirm: confirmThen { [weak self] in self?.saveTutorialRecord() }
            default: break
            }
        case .saved:
            break
        case .lookback:
            switch event {
            case .knob(let steps): moveRecord(by: steps)
            case .left: moveRecord(by: -1)
            case .right: moveRecord(by: 1)
            case .confirm: confirmThen { [weak self] in self?.tutorialGo(.ready) }
            default: break
            }
        case .ready:
            if event == .confirm { confirmThen { [weak self] in self?.endTutorial() } }
        }
    }

    /// The first use of a control fills it in on the drawing and says so in a toast.
    private func learn(_ event: ControlEvent, on step: TutorialStep) {
        guard let lesson = TutorialLesson(event), !tutorialLearned.contains(lesson) else { return }
        // Back on the first page leaves the onboarding; that does not count as learning it.
        if lesson == .back && step == .welcome { return }
        tutorialLearned.insert(lesson)
        tutorialToast = lesson
        toastTimer?.cancel()
        toastTimer = scheduler.after(1.8) { [weak self] in self?.tutorialToast = nil }
    }

    /// Phone: tapping a key on the onboarding's letter wheel.
    func tapTutorialKey(at index: Int) {
        letterIndex = index
        pressTutorialKey()
    }

    private func pressTutorialKey() {
        guard route == .tutorial(.name) else { return }
        confirmCount += 1
        switch LetterKey.at(letterIndex) {
        case .letter(let character):
            if nameDraft.count < Self.maxNameLength { nameDraft.append(character) }
        case .delete:
            if !nameDraft.isEmpty { nameDraft.removeLast() }
        case .save:
            let name = nameDraft.capitalized
            guard !name.isEmpty else { return }
            confirmCount -= 1
            confirmThen { [weak self] in
                guard let self else { return }
                if let member = store.addMember(name: name) {
                    tutorialMemberID = member.id
                    memberID = member.id
                }
                nameDraft = ""
                menuChoice = .record
                tutorialGo(.chooseRecord)
            }
        }
    }

    private func tutorialFilmTick(_ left: Int) {
        guard route == .tutorial(.film) else { return }
        if left == 0 {
            tutorialFilmLeft = nil
            tutorialMM = 1200
            tutorialGo(.height)
            return
        }
        tutorialFilmLeft = left
        timer = scheduler.after(1) { [weak self] in self?.tutorialFilmTick(left - 1) }
    }

    /// The dial's height becomes the new member's first record (no clip: a demo).
    private func saveTutorialRecord() {
        guard let id = tutorialMemberID else { return }
        let record = store.addRecord(memberID: id, heightMM: tutorialMM, source: .edited, clip: nil)
        savedRecordID = record.id
        tutorialGo(.saved)
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
