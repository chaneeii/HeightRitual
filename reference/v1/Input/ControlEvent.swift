import Foundation

/// What the controller (or the on-screen pad) reports.
/// The controller never knows which screen is open; AppState decides what each event means.
enum ControlEvent: Equatable {
    case knob(Int)                 // + clockwise, - counter-clockwise, in clicks
    case knobPress
    case record
    case playback
    case confirm
    case cancel                    // Confirm held for one second
    case left
    case right
    case modeSwitch(record: Bool)  // physical switch: true = Record, false = View
}

/// LED patterns the app asks the controller to show.
enum LEDPattern: UInt8 {
    case off = 0
    case slowBlink = 1   // recording session open
    case on = 2          // taking the photo
    case savedFlash = 3  // three quick flashes, then off
}
