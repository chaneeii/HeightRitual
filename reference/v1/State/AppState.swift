import Observation
import SwiftUI
import UIKit

/// The screens of the ritual. Each one gives the controller's buttons a different meaning.
enum Screen: Equatable {
    case view          // browse past years on the wall
    case playback      // growth plays from the first year to now
    case selectChild   // record session: who is measured
    case enterHeight   // record session: height typed in or set with the knob
    case capture       // record session: camera, countdown, photo
    case review        // record session: check the cut-out before saving
    case calibrate     // installation: match projector centimetres to the wall
}

enum CalibrationParam: Int, CaseIterable {
    case floor, scale, shift

    var title: String {
        switch self {
        case .floor: return "Floor line"
        case .scale: return "Scale"
        case .shift: return "Left and right"
        }
    }
}

/// Single source of truth shared by the phone screen and the projector screen.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let store = RecordStore()
    let camera = CameraController()
    let controller = ControllerManager()

    private(set) var screen: Screen = .view
    var childIndex = 0
    var recordIndex = 0
    var draftHeightCM: Double = 100
    var cutout: UIImage?
    var countdown: Int?
    var isProcessing = false
    var errorMessage: String?

    var calibration = Calibration.load()
    var calibrationParam: CalibrationParam = .floor
    var calibrationFine = false

    var externalDisplayConnected = false
    var wallSize = CGSize(width: 1920, height: 1080)
    var controllerStatus: ControllerManager.Status = .bluetoothOff
    var modeSwitchRecord = false

    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    private init() {
        controller.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        controller.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.controllerStatus = status
                if status == .connected { self?.updateLED() }
            }
        }
        controller.start()
        if store.children.isEmpty { store.loadSampleFamily() }
        recordIndex = max(0, currentRecords.count - 1)
    }

    // MARK: Derived values

    var currentChild: Child? {
        store.children.indices.contains(childIndex) ? store.children[childIndex] : nil
    }

    var currentRecords: [GrowthRecord] {
        guard let child = currentChild else { return [] }
        return store.records(for: child.id)
    }

    var selectedRecord: GrowthRecord? {
        currentRecords.indices.contains(recordIndex) ? currentRecords[recordIndex] : nil
    }

    var lastRecord: GrowthRecord? { currentRecords.last }

    var isRecordSession: Bool {
        [.selectChild, .enterHeight, .capture, .review].contains(screen)
    }

    // MARK: Controller events

    func handle(_ event: ControlEvent) {
        if case .modeSwitch(let record) = event {
            modeSwitchRecord = record
            if record, screen == .view || screen == .playback {
                beginRecording()
            } else if !record, isRecordSession {
                cancelRecording()
            }
            return
        }

        switch screen {
        case .view:
            switch event {
            case .knob(let clicks): moveRecord(by: clicks)
            case .knobPress: recordIndex = max(0, currentRecords.count - 1)
            case .left: moveChild(by: -1)
            case .right: moveChild(by: 1)
            case .record: beginRecording()
            case .playback: startPlayback()
            default: break
            }

        case .playback:
            switch event {
            case .playback, .confirm, .cancel, .knobPress, .record: stopPlayback()
            default: break
            }

        case .selectChild:
            switch event {
            case .knob(let clicks): moveChild(by: clicks)
            case .left: moveChild(by: -1)
            case .right: moveChild(by: 1)
            case .confirm: confirmChild()
            case .cancel: cancelRecording()
            default: break
            }

        case .enterHeight:
            switch event {
            case .knob(let clicks): adjustHeight(by: Double(clicks) * 0.5)
            case .left: adjustHeight(by: -1)
            case .right: adjustHeight(by: 1)
            case .knobPress: draftHeightCM = lastRecord?.heightCM ?? 100
            case .confirm: go(to: .capture)
            case .cancel: go(to: .selectChild)
            default: break
            }

        case .capture:
            switch event {
            case .confirm: startCountdown()
            case .record: takePhoto()
            case .cancel:
                cancelCountdown()
                go(to: .enterHeight)
            default: break
            }

        case .review:
            switch event {
            case .confirm: saveRecord()
            case .left, .cancel: retake()
            default: break
            }

        case .calibrate:
            switch event {
            case .knob(let clicks): nudgeCalibration(by: clicks)
            case .left: cycleCalibrationParam(by: -1)
            case .right: cycleCalibrationParam(by: 1)
            case .knobPress: calibrationFine.toggle()
            case .confirm, .cancel: finishCalibration()
            default: break
            }
        }
    }

    // MARK: Navigation

    func go(to next: Screen) {
        screen = next
        if next == .capture || next == .review {
            camera.start()
        } else {
            camera.stop()
        }
        updateLED()
    }

    private func updateLED() {
        if isProcessing || countdown != nil {
            controller.setLED(.on)
        } else if isRecordSession {
            controller.setLED(.slowBlink)
        } else {
            controller.setLED(.off)
        }
    }

    // MARK: View mode

    func moveRecord(by clicks: Int) {
        guard !currentRecords.isEmpty else { return }
        recordIndex = min(max(recordIndex + clicks, 0), currentRecords.count - 1)
    }

    func moveChild(by step: Int) {
        let count = store.children.count
        guard count > 0 else { return }
        childIndex = ((childIndex + step) % count + count) % count
        recordIndex = max(0, currentRecords.count - 1)
    }

    func selectChild(_ index: Int) {
        guard store.children.indices.contains(index) else { return }
        childIndex = index
        recordIndex = max(0, currentRecords.count - 1)
    }

    func startPlayback() {
        guard currentRecords.count > 1 else { return }
        playbackTask?.cancel()
        recordIndex = 0
        go(to: .playback)
        playbackTask = Task { [weak self] in
            while let self, self.recordIndex < self.currentRecords.count - 1 {
                try? await Task.sleep(for: .seconds(1.4))
                if Task.isCancelled { return }
                self.recordIndex += 1
            }
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            if self?.screen == .playback { self?.go(to: .view) }
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        if screen == .playback { go(to: .view) }
    }

    // MARK: Record session

    func beginRecording() {
        guard !store.children.isEmpty else {
            errorMessage = "Add a child in Settings before recording."
            return
        }
        stopPlayback()
        cutout = nil
        go(to: .selectChild)
    }

    func confirmChild() {
        draftHeightCM = lastRecord?.heightCM ?? 100
        go(to: .enterHeight)
    }

    func cancelRecording() {
        cancelCountdown()
        cutout = nil
        isProcessing = false
        recordIndex = max(0, currentRecords.count - 1)
        go(to: .view)
    }

    func adjustHeight(by deltaCM: Double) {
        let value = ((draftHeightCM + deltaCM) * 2).rounded() / 2
        draftHeightCM = min(max(value, 40), 200)
    }

    func startCountdown() {
        guard countdown == nil, !isProcessing else { return }
        countdownTask = Task { [weak self] in
            for n in stride(from: 3, through: 1, by: -1) {
                self?.countdown = n
                self?.updateLED()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.countdown = nil
            self?.takePhoto()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    func takePhoto() {
        guard !isProcessing else { return }
        cancelCountdown()
        isProcessing = true
        updateLED()
        Task {
            do {
                let photo = try await camera.capture()
                let result = try await PersonCutout.make(from: photo)
                cutout = result
                isProcessing = false
                go(to: .review)
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
                updateLED()
            }
        }
    }

    func retake() {
        cutout = nil
        go(to: .capture)
    }

    func saveRecord() {
        guard let child = currentChild else { return }
        let record = store.addRecord(childID: child.id,
                                     heightMM: Int((draftHeightCM * 10).rounded()),
                                     cutout: cutout)
        cutout = nil
        recordIndex = currentRecords.firstIndex { $0.id == record.id } ?? max(0, currentRecords.count - 1)
        go(to: .view)
        controller.setLED(.savedFlash)
    }

    // MARK: Calibration

    func startCalibration() {
        stopPlayback()
        cancelRecording()
        go(to: .calibrate)
    }

    func cycleCalibrationParam(by step: Int) {
        let all = CalibrationParam.allCases
        let index = ((calibrationParam.rawValue + step) % all.count + all.count) % all.count
        calibrationParam = all[index]
    }

    func nudgeCalibration(by clicks: Int) {
        let n = Double(clicks)
        switch calibrationParam {
        case .floor: calibration.floorPt = max(0, calibration.floorPt + n * (calibrationFine ? 1 : 5))
        case .scale: calibration.ptPerCM = min(max(calibration.ptPerCM + n * (calibrationFine ? 0.01 : 0.05), 1), 20)
        case .shift: calibration.shiftPt += n * (calibrationFine ? 1 : 5)
        }
        calibration.save()
    }

    func finishCalibration() {
        calibration.save()
        go(to: .view)
    }
}
