import CoreGraphics
import Foundation
import Observation

enum HeightUnit: String, Codable, CaseIterable {
    case cm, ftin
}

extension Locale {
    /// The app is in English only; dates and numbers use US English everywhere.
    static let english = Locale(identifier: "en_US")
}

/// A string built in code (not a SwiftUI Text). The app is English only, so this is the
/// English text itself; kept as one place in case translations come back.
func L(_ value: String.LocalizationValue) -> String {
    String(localized: value, locale: .english)
}

/// Maps real centimetres on the wall to points on the projected image (SPEC 7, S2).
struct Calibration: Codable, Equatable {
    /// Distance from the bottom edge of the projected image to the floor line, in points.
    var floorPt: Double = 40
    /// How many projector points one real centimetre takes on the wall.
    var ptPerCM: Double = 5
    /// The projector always lies on its side, turned -90 degrees (no longer a setting). Settings
    /// saved before may still hold another value, which decoding ignores.
    var rotation: Int { -90 }

    /// The projected image size after rotation, in the wall's own up and down direction.
    func logicalSize(for screen: CGSize) -> CGSize {
        CGSize(width: screen.height, height: screen.width)
    }

    /// Only a portrait strip of the picture is used: 9:16, the picture's full height, so the
    /// centimetres it reaches stay the same. The rest of a wide picture stays black, and the phone
    /// shows exactly this strip.
    static let stripAspect = 9.0 / 16.0

    /// The strip's size in projector points, upright.
    func stripSize(for screen: CGSize) -> CGSize {
        let picture = logicalSize(for: screen)
        return CGSize(width: min(picture.width, picture.height * Self.stripAspect), height: picture.height)
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

/// Values in the settings list, kept in UserDefaults. Setup values survive "Delete everything".
@MainActor
@Observable
final class SettingsStore {
    var unit: HeightUnit { didSet { save(unit, "unit") } }
    var soundOn: Bool { didSet { save(soundOn, "soundOn") } }
    var autoPlay: Bool { didSet { save(autoPlay, "autoPlay") } }
    /// Memory shows clips as filmed, with their background, instead of the cut-out.
    var showBackground: Bool { didSet { save(showBackground, "showBackground") } }
    /// The point colour of the redesign (`Theme.accent`): an index into `Palette.memberColors`,
    /// or nil for the default black.
    var accentIndex: Int? { didSet { save(accentIndex, "accentIndex") } }
    var wall: Calibration { didSet { save(wall, "wall") } }
    var camera: CameraPosition? { didSet { save(camera, "camera") } }
    /// The first-start wizard has been finished or skipped through.
    var wizardDone: Bool { didSet { save(wizardDone, "wizardDone") } }
    /// The knob or Left / Right has been used on the height check, so its step hint is gone.
    var heightStepsLearned: Bool { didSet { save(heightStepsLearned, "heightStepsLearned") } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func load<T: Decodable>(_ key: String) -> T? {
            guard let data = defaults.data(forKey: "settings." + key) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        accentIndex = load("accentIndex")
        unit = load("unit") ?? .cm
        soundOn = load("soundOn") ?? true
        autoPlay = load("autoPlay") ?? false
        showBackground = load("showBackground") ?? false
        wall = load("wall") ?? Calibration()
        camera = load("camera") as CameraPosition?
        wizardDone = load("wizardDone") ?? false
        heightStepsLearned = load("heightStepsLearned") ?? false
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: "settings." + key)
        }
    }
}
