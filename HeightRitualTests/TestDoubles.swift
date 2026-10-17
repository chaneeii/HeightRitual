import Foundation
@testable import HeightRitual

@MainActor
final class FakeCamera: CameraProviding {
    var previewing = false
    var recording = false
    var movie: URL?

    func startPreview() { previewing = true }
    func stopPreview() { previewing = false }
    func startRecording(sound: Bool) { recording = true }
    func stopRecording(_ done: @escaping @MainActor (URL?) -> Void) {
        recording = false
        done(movie)
    }
}

/// Never finishes on its own; tests call `AppState.finishProcessing(_:)` instead.
struct HangingProcessor: ClipProcessing {
    func process(movie: URL?, camera: CameraPosition?,
                 progress: @escaping @MainActor (Double) -> Void) async throws -> ProcessedClip? {
        try await Task.sleep(for: .seconds(3600))
        return nil
    }
}

@MainActor
final class FakeController: ControllerLink {
    var onEvent: ((ControlEvent) -> Void)?
    var onStatus: ((ControllerStatus) -> Void)?
    var onRaw: (([UInt8]) -> Void)?
    var onNote: ((String) -> Void)?
    var lights: [LightState] = []

    func start() {}
    func setLight(_ light: LightState) { lights.append(light) }
    func forget() {}
}

/// Time moves only when the test calls `advance(_:)`.
@MainActor
final class ManualScheduler: Scheduling {
    private final class Entry: ScheduledTask {
        let due: Double
        let action: @MainActor () -> Void
        var cancelled = false
        init(due: Double, action: @escaping @MainActor () -> Void) {
            self.due = due
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    private var now = 0.0
    private var entries: [Entry] = []

    func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> ScheduledTask {
        let entry = Entry(due: now + seconds, action: action)
        entries.append(entry)
        return entry
    }

    func advance(_ seconds: Double) {
        let end = now + seconds
        while let next = entries.filter({ !$0.cancelled && $0.due <= end }).min(by: { $0.due < $1.due }) {
            entries.removeAll { $0 === next }
            now = next.due
            next.action()
        }
        now = end
    }
}

@MainActor
struct Harness {
    let state: AppState
    let camera: FakeCamera
    let controller: FakeController
    let scheduler: ManualScheduler
    let directory: URL

    /// `setupDone` false runs the first-start wizard, as on a new phone.
    init(setupDone: Bool = true) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        camera = FakeCamera()
        controller = FakeController()
        scheduler = ManualScheduler()
        let settings = SettingsStore(defaults: defaults)
        settings.wizardDone = setupDone
        state = AppState(store: Store(directory: directory),
                         settings: settings,
                         camera: camera,
                         processor: HangingProcessor(),
                         controller: controller,
                         scheduler: scheduler)
    }

    var nora: Member { state.store.members[0] }

    /// Confirm, then let the green check finish so the choice opens.
    func confirm() {
        state.handle(.confirm)
        scheduler.advance(AppState.confirmSeconds)
    }

    /// Home -> Nora -> member menu -> Record -> M2 ready.
    func openFilm() {
        confirm()
        state.handle(.left)
        confirm()
    }

    /// M2 -> countdown -> filming -> stop early -> M3 cutting out.
    func filmAndStop() {
        openFilm()
        state.handle(.record)
        scheduler.advance(3)
        state.handle(.record)
    }

    /// ... -> M3 editing with the given estimate.
    func openHeight(estimateMM: Int? = 1225) {
        filmAndStop()
        state.finishProcessing(ProcessedClip(estimatedMM: estimateMM))
    }

    /// Home -> Nora -> member menu -> Lookback -> R2 manual, newest record selected.
    func openMemoryWall() {
        confirm()
        state.handle(.right)
        confirm()
    }
}
