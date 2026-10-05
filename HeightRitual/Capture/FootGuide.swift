import SwiftUI

/// Where the foot guide sits in the upright camera frame (SPEC 8), as fractions of the frame
/// (0 = top / left). Built from the camera position values; without them a fixed outline at the
/// centre of the preview.
struct FootGuide: Equatable {
    /// The camera frame is upright 1080 x 1920.
    static let frameAspect = 9.0 / 16.0
    /// First record: an outline of 120 cm.
    static let firstRecordMM = 1200

    var floorY: Double
    var centerX: Double
    /// Top of the standing outline.
    var topY: Double
    /// Height of one centimetre on the wall, as a fraction of the frame height.
    var cmY: Double
    var isCalibrated: Bool

    /// `outlineMM`: the member's last height plus 10 cm, or 120 cm for a first record.
    static func make(camera: CameraPosition?, outlineMM: Int) -> FootGuide {
        let cm = Double(outlineMM) / 10
        if let camera, camera.floorY > camera.y100 {
            let cmY = (camera.floorY - camera.y100) / 100
            return FootGuide(floorY: camera.floorY, centerX: camera.centerX,
                             topY: camera.floorY - cm * cmY, cmY: cmY, isCalibrated: true)
        }
        // Fallback: the outline fills most of the preview, feet near the bottom.
        let floorY = 0.9
        let topY = 0.15
        return FootGuide(floorY: floorY, centerX: 0.5, topY: topY, cmY: (floorY - topY) / cm, isCalibrated: false)
    }

    static func outlineMM(lastMM: Int?) -> Int {
        lastMM.map { $0 + 100 } ?? firstRecordMM
    }

    /// One centimetre as a fraction of the frame width.
    var cmX: Double { cmY / Self.frameAspect }
}

/// Soft outline of a standing person, 125 units tall, drawn with its feet on `floor`.
/// Shared by the wall drawing and the foot guide on the phone.
enum PersonOutline {
    static func path(heightPt: CGFloat, centerX: CGFloat, floorY: CGFloat) -> Path {
        let unit = heightPt / 125
        func r(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: centerX + x0 * unit, y: floorY - y1 * unit, width: (x1 - x0) * unit, height: (y1 - y0) * unit)
        }
        var shape = Path()
        shape.addEllipse(in: r(-10, 105, 10, 125))
        shape.addRoundedRect(in: r(-12, 55, 12, 100), cornerSize: CGSize(width: 6 * unit, height: 6 * unit))
        shape.addRoundedRect(in: r(-18, 58, -13, 96), cornerSize: CGSize(width: 2.5 * unit, height: 2.5 * unit))
        shape.addRoundedRect(in: r(13, 58, 18, 96), cornerSize: CGSize(width: 2.5 * unit, height: 2.5 * unit))
        shape.addRoundedRect(in: r(-10, 0, -1, 57), cornerSize: CGSize(width: 2 * unit, height: 2 * unit))
        shape.addRoundedRect(in: r(1, 0, 10, 57), cornerSize: CGSize(width: 2 * unit, height: 2 * unit))
        return shape
    }
}
