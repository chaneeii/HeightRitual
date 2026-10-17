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

/// What to do with the chosen member, on the overlay above Home.
enum MemberAction: Equatable {
    case record                   // film a new record (M2)
    case lookback                 // the memory wall (R2)
}

/// One position on the letter wheel of the add-member screen: Delete, Save, then A to Z.
/// The wheel has no ends; turning past Z comes back to Delete.
enum LetterKey: Equatable {
    case delete
    case save
    case letter(Character)

    static let all: [LetterKey] = [.delete, .save] + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { .letter($0) }
    /// The wheel starts on A.
    static let startIndex = 2

    static func at(_ index: Int) -> LetterKey {
        all[((index % all.count) + all.count) % all.count]
    }
}

/// Every screen of the app (SPEC 5). Changed only through `AppState.go(to:)`.
/// Home is a wheel of member cards; choosing one opens the member menu (Record or Lookback).
enum Route: Equatable {
    case home                     // H: wheel of members, Add card at the end
    case memberMenu               // H1: overlay above Home for the chosen member
    case addMember                // A2: name from the letter wheel
    case makeFilm(FilmState)      // M2
    case makeHeight(HeightState)  // M3
    case memoryWall               // R2
    case record(UUID)             // R3
    case memberEdit(UUID?)        // A1, nil = new member
    case settings(SettingsPage)   // S, S1 to S6
    case wizard(WizardStep)       // W

    /// The mode a route belongs to; nil for screens outside both modes.
    var mode: Mode? {
        switch self {
        case .makeFilm, .makeHeight: return .make
        case .memoryWall, .record: return .memory
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
