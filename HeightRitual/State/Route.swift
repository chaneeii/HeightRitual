import Foundation

enum FilmState: Equatable {
    case ready
    case filming(secondsLeft: Int)
}

enum HeightState: Equatable {
    case cuttingOut(progress: Double)
    case editing
    case noPerson
}

enum SettingsPage: Equatable {
    case list, family, setupGuide, fitToWall, cameraPosition, units, sound, controller, permissions
    /// Load sample family and Delete everything ask first, on the phone and the projector.
    case confirmSample, confirmDelete
}

/// What the controller moves through on the projector's settings grid, in order: Setup guide
/// (beside the title), then the tiles row by row. Every tile opens a page.
enum SettingsTile: Int, CaseIterable {
    case setupGuide, family, fitToWall, cameraPosition, units, sound,
         controller, permissions, sampleFamily, deleteEverything

    /// The page Select opens from the projector grid.
    var page: SettingsPage {
        switch self {
        case .setupGuide: return .setupGuide
        case .family: return .family
        case .fitToWall: return .fitToWall
        case .cameraPosition: return .cameraPosition
        case .units: return .units
        case .sound: return .sound
        case .controller: return .controller
        case .permissions: return .permissions
        case .sampleFamily: return .confirmSample
        case .deleteEverything: return .confirmDelete
        }
    }
}

/// A family member opened from the projector's Family page: its choices, then the colour list or
/// the delete question.
enum MemberStep: Equatable {
    case choices, rename, colour, confirmDelete
}

/// The rows of a member's page on the projector, in the same order as the phone's member page.
enum MemberRow: Int, CaseIterable {
    case card, name, colour, delete
}

/// First-start wizard: what the app is, then S5, S2, S3 in order.
enum WizardStep: Int, CaseIterable {
    case welcome, permissions, fitToWall, cameraPosition

    static let setupSteps = allCases.filter { $0 != .welcome }
}

/// The value the knob changes on the fit to wall page (S2).
enum FitValue: Int, CaseIterable {
    case floor, size

    var title: String {
        switch self {
        case .floor: return L("Floor line")
        case .size: return L("Size")
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

/// The guided first use from Settings (a demo feature): the app's real steps, one control at a
/// time, with the controller drawn underneath.
enum TutorialStep: Int, CaseIterable {
    case welcome = 1      // what Memory Meter is
    case family           // add someone
    case name             // pick letters, Save
    case chooseRecord     // Left / Right to Record, Confirm
    case film             // five seconds
    case height           // knob and Left / Right on the dial, Confirm saves
    case saved            // Back goes back
    case chooseLookback   // Left / Right to Lookback, Confirm
    case lookback         // every record, life-size
    case ready            // Confirm: Home, on the new member

    var previous: TutorialStep? { TutorialStep(rawValue: rawValue - 1) }
    var next: TutorialStep? { TutorialStep(rawValue: rawValue + 1) }
}

/// A control of the box, as the onboarding teaches it. Left and Right are one lesson.
enum TutorialLesson: Hashable, CaseIterable {
    case confirm, knob, arrows, back

    init?(_ event: ControlEvent) {
        switch event {
        case .confirm: self = .confirm
        case .knob: self = .knob
        case .left, .right: self = .arrows
        case .cancel: self = .back
        default: return nil
        }
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
    case makeSaved                // M4: saved, then growth or someone else
    case memoryWall               // R2
    case record(UUID)             // R3
    case memberEdit(UUID?)        // A1, nil = new member
    case settings(SettingsPage)   // S, S1 to S6
    case wizard(WizardStep)       // W
    case tutorial(TutorialStep)   // T: onboarding with the controller

    /// The mode a route belongs to; nil for screens outside both modes.
    var mode: Mode? {
        switch self {
        case .makeFilm, .makeHeight, .makeSaved: return .make
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
        case .makeFilm(.filming), .makeHeight: return true
        default: return false
        }
    }
}
