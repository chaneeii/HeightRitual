import Foundation

enum Mode: Hashable {
    case make, memory
}

/// What the controller (or the same button on the phone) reports.
/// The controller never knows which screen is open; AppState decides what each event means.
enum ControlEvent: Equatable {
    case knob(Int)          // steps, + clockwise
    case left
    case right
    case confirm
    case cancel
    case record             // Record / Stop
    case autoPlayToggle
    case mode(Mode)         // slide switch, or the tabs on the phone

    /// Short name for the controller test page.
    var label: String {
        switch self {
        case .knob(let steps): return "Knob \(steps > 0 ? "+" : "")\(steps)"
        case .left: return "Left"
        case .right: return "Right"
        case .confirm: return "Confirm"
        case .cancel: return "Cancel / Back"
        case .record: return "Record / Stop"
        case .autoPlayToggle: return "Auto play"
        case .mode(let mode): return mode == .make ? "Mode: Make" : "Mode: Memory"
        }
    }

    /// Maps a 2-byte packet `[controlId, value]` from the controller (SPEC 6).
    static func from(id: UInt8, value: Int8) -> ControlEvent? {
        switch id {
        case 1: return value == 0 ? nil : .knob(Int(value))
        case 11: return .record
        case 13: return .confirm
        case 23: return .cancel
        case 14: return .left
        case 15: return .right
        case 31: return .mode(value == 1 ? .make : .memory)
        case 32: return .autoPlayToggle
        default: return nil   // 12 (Playback) and 21 (Push) are no longer used
        }
    }
}

/// Ignores an identical non-knob event that arrives again within 100 ms.
/// The firmware already debounces at 25 ms; this catches doubled notifications.
struct EventDebouncer {
    var window: TimeInterval = 0.1
    private var last: (event: ControlEvent, time: TimeInterval)?

    init(window: TimeInterval = 0.1) { self.window = window }

    mutating func accept(_ event: ControlEvent, at time: TimeInterval) -> Bool {
        if case .knob = event { return true }
        if let last, last.event == event, time - last.time < window { return false }
        last = (event, time)
        return true
    }
}

/// The two bytes written to the light characteristic: `[recording, mode]`.
struct LightState: Equatable {
    enum Recording: UInt8 {
        case off = 0
        case countdown = 1   // slow blink
        case steady = 2      // filming or cutting out
        case saved = 3       // three quick flashes, then off
    }

    var recording: Recording = .off
    var mode: Mode = .memory

    var bytes: [UInt8] { [recording.rawValue, mode == .make ? 1 : 0] }
}

enum ControllerStatus: Equatable {
    /// Bluetooth permission not given yet, or refused.
    case notAllowed
    /// Bluetooth switched off, or not available (simulator).
    case bluetoothOff
    case searching
    case connecting
    case connected

    /// Chip text on the phone (SPEC 5: "Searching for controller" while not found).
    var label: String {
        switch self {
        case .notAllowed: return L("Bluetooth not allowed")
        case .bluetoothOff: return L("Bluetooth off")
        case .searching: return L("Searching for controller")
        case .connecting: return L("Connecting to controller")
        case .connected: return L("Controller")
        }
    }
}

/// What AppState needs from the controller. `ControllerManager` is the Bluetooth version.
@MainActor
protocol ControllerLink: AnyObject {
    var onEvent: ((ControlEvent) -> Void)? { get set }
    var onStatus: ((ControllerStatus) -> Void)? { get set }
    /// Every packet as received, before debouncing; for the controller test page.
    var onRaw: (([UInt8]) -> Void)? { get set }
    /// Connection steps and errors, in plain words; for the controller test page.
    var onNote: ((String) -> Void)? { get set }
    func start()
    func setLight(_ light: LightState)
    func forget()
}
