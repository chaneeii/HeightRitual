import Foundation

enum FilmState: Equatable {
    case ready
    case countdown(Int)
    case filming(secondsLeft: Int)
}

enum HeightState: Equatable {
    case cuttingOut(progress: Double)
    case editing
    case noPerson
}

enum SettingsPage: Equatable {
    case list, family, fitToWall, cameraPosition, units, controller, permissions
}

/// First-start wizard: what the app is, then S5, S2, S3 in order.
enum WizardStep: Int, CaseIterable {
    case welcome, permissions, fitToWall, cameraPosition

    static let setupSteps = allCases.filter { $0 != .welcome }
}

/// The value the knob changes on the fit to wall page (S2).
enum FitValue: Int, CaseIterable {
    case floor, size, shift

    var title: String {
        switch self {
        case .floor: return L("Floor line")
        case .size: return L("Size")
        case .shift: return L("Left and right")
        }
    }
}

/// Every screen of the app (SPEC 5). Changed only through `AppState.go(to:)`.
/// The Make / Memory tab bar is Home; the app opens on R1.
enum Route: Equatable {
    case makeWho                  // M1
    case makeFilm(FilmState)      // M2
    case makeHeight(HeightState)  // M3
    case memoryWho                // R1
    case memoryWall               // R2
    case record(UUID)             // R3
    case memberEdit(UUID?)        // A1, nil = new member
    case settings(SettingsPage)   // S, S1 to S6
    case wizard(WizardStep)       // W

    /// The mode a route belongs to; nil for screens outside both modes.
    var mode: Mode? {
        switch self {
        case .makeWho, .makeFilm, .makeHeight: return .make
        case .memoryWho, .memoryWall, .record: return .memory
        default: return nil
        }
    }

    /// M2 and the camera position page show the camera preview.
    var usesCamera: Bool {
        switch self {
        case .makeFilm, .settings(.cameraPosition), .wizard(.cameraPosition): return true
        default: return false
        }
    }

    /// Countdown, filming and the height step hold work that is lost when going anywhere else.
    var holdsMakeSession: Bool {
        switch self {
        case .makeFilm(.countdown), .makeFilm(.filming), .makeHeight: return true
        default: return false
        }
    }
}
