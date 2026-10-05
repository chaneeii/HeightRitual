import CoreGraphics
import Foundation
import Observation

enum HeightUnit: String, Codable, CaseIterable {
    case cm, ftin
}

/// The app's language, chosen in Settings. System follows the phone.
enum AppLanguage: String, Codable, CaseIterable {
    case system
    case en
    case ko
    case zhHans = "zh-Hans"
    case sv

    /// The language last chosen; read by `L(_:)` and the date formats.
    nonisolated(unsafe) static var current: AppLanguage = .system

    /// The localization actually used: the chosen one, or the phone's best match.
    var code: String {
        self == .system ? (Bundle.main.preferredLocalizations.first ?? "en") : rawValue
    }

    var locale: Locale { Locale(identifier: code) }

    /// The .lproj folder with this language's strings.
    var bundle: Bundle {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    /// Each language's own name, the same in every language (as in iOS).
    var nativeName: String {
        switch self {
        case .system: return ""
        case .en: return "English"
        case .ko: return "한국어"
        case .zhHans: return "简体中文"
        case .sv: return "Svenska"
        }
    }
}

/// A string from code (not a SwiftUI Text) in the app's language.
func L(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: AppLanguage.current.bundle)
}

/// The phone's light or dark look. The wall image is always black.
enum Appearance: String, Codable, CaseIterable {
    case system, light, dark
}

/// Maps real centimetres on the wall to points on the projected image (SPEC 7, S2).
struct Calibration: Codable, Equatable {
    /// Distance from the bottom edge of the projected image to the floor line, in points.
    var floorPt: Double = 40
    /// How many projector points one real centimetre takes on the wall.
    var ptPerCM: Double = 5
    /// Moves the drawing left or right, in points.
    var shiftPt: Double = 0
    /// 0 when the projector stands normally; 90 or -90 when it lies on its side.
    var rotation: Int = 0

    /// The projected image size after rotation, in the wall's own up and down direction.
    func logicalSize(for screen: CGSize) -> CGSize {
        rotation == 0 ? screen : CGSize(width: screen.height, height: screen.width)
    }

    /// `y(cm) = imageHeight - floorPt - cm * ptPerCM`
    func y(cm: Double, imageHeight: Double) -> Double {
        imageHeight - floorPt - cm * ptPerCM
    }

    /// Highest centimetre the projected image reaches above the floor.
    func visibleTopCM(imageHeight: Double) -> Double {
        max(0, (imageHeight - floorPt) / ptPerCM)
    }
}

/// Where the wall's floor line and 100 cm line sit in the upright camera frame (SPEC 7, S3).
/// Fractions of the frame height (0 = top) and width.
struct CameraPosition: Codable, Equatable {
    var floorY: Double
    var y100: Double
    var centerX: Double = 0.5
}

/// Projector placement inputs (SPEC 7, S1).
struct ProjectorSetup: Codable, Equatable {
    var throwRatio: Double = 0.8
    var onItsSide = false
}

/// Values in the settings list, kept in UserDefaults. Setup values survive "Delete everything".
@MainActor
@Observable
final class SettingsStore {
    var unit: HeightUnit { didSet { save(unit, "unit") } }
    var soundOn: Bool { didSet { save(soundOn, "soundOn") } }
    var autoPlay: Bool { didSet { save(autoPlay, "autoPlay") } }
    var appearance: Appearance { didSet { save(appearance, "appearance") } }
    var language: AppLanguage {
        didSet {
            AppLanguage.current = language
            save(language, "language")
        }
    }
    var projector: ProjectorSetup { didSet { save(projector, "projector") } }
    var wall: Calibration { didSet { save(wall, "wall") } }
    var camera: CameraPosition? { didSet { save(camera, "camera") } }
    /// The first-start wizard has been finished or skipped through.
    var wizardDone: Bool { didSet { save(wizardDone, "wizardDone") } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func load<T: Decodable>(_ key: String) -> T? {
            guard let data = defaults.data(forKey: "settings." + key) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        unit = load("unit") ?? .cm
        soundOn = load("soundOn") ?? false
        autoPlay = load("autoPlay") ?? false
        appearance = load("appearance") ?? .system
        let language: AppLanguage = load("language") ?? .system
        self.language = language
        AppLanguage.current = language
        projector = load("projector") ?? ProjectorSetup()
        wall = load("wall") ?? Calibration()
        camera = load("camera") as CameraPosition?
        wizardDone = load("wizardDone") ?? false
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: "settings." + key)
        }
    }
}

extension ProjectorSetup {
    /// Picture height the placement page aims for (SPEC 7, S1).
    static let targetPictureCM = 180.0
    static let presets: [Double] = [0.8, 1.2, 1.5]

    /// Height / width of the picture: 9/16 upright, 16/9 on its side.
    var aspect: Double { onItsSide ? 16.0 / 9.0 : 9.0 / 16.0 }

    /// Upright: `pictureHeight = distance / throwRatio * 9/16`.
    /// On its side: `pictureHeight = distance / throwRatio`.
    func pictureHeightCM(distanceCM: Double) -> Double {
        onItsSide ? distanceCM / throwRatio : distanceCM / throwRatio * 9 / 16
    }

    /// Distance from the wall for a picture `heightCM` tall.
    func distanceCM(forPictureHeight heightCM: Double = targetPictureCM) -> Double {
        onItsSide ? heightCM * throwRatio : heightCM * throwRatio * 16 / 9
    }

    func pictureWidthCM(forPictureHeight heightCM: Double = targetPictureCM) -> Double {
        heightCM / aspect
    }
}
