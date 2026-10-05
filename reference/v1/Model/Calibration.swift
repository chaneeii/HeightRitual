import Foundation
import CoreGraphics

/// Maps real centimetres on the wall to points on the projector image.
/// Set once at installation with the calibration screen and a real tape measure.
struct Calibration: Codable, Equatable {
    /// Distance from the bottom edge of the projected image to the floor line, in points.
    var floorPt: Double = 40
    /// How many projector points one real centimetre takes on the wall.
    var ptPerCM: Double = 5
    /// Moves the drawing left or right, in points.
    var shiftPt: Double = 0
    /// 0 when the projector stands normally; 90 or -90 when it lies on its side for a tall image.
    var rotation: Int = 0

    private static let key = "calibration.v1"

    static func load() -> Calibration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(Calibration.self, from: data) else { return Calibration() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// The projected image size after rotation, in the wall's own up and down direction.
    func logicalSize(for screen: CGSize) -> CGSize {
        rotation == 0 ? screen : CGSize(width: screen.height, height: screen.width)
    }

    /// Highest centimetre the projected image reaches above the floor.
    func visibleTopCM(for screen: CGSize) -> Double {
        let height = Double(logicalSize(for: screen).height)
        return max(0, (height - floorPt) / ptPerCM)
    }
}
