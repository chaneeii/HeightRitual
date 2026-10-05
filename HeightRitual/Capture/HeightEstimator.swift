import Foundation

/// Height from the video, using the calibrated wall as the ruler (SPEC 9 step 3).
/// The accuracy has not been measured yet; the UI always lets the user correct it.
enum HeightEstimator {
    /// `cm = (floorY - headY) * 100 / (floorY - y100)`, rounded to 0.5 cm.
    /// `headY` is the head top as a fraction of the upright frame height (0 = top).
    /// Nil without camera position values or when the result is outside 40 to 220 cm.
    static func estimateMM(headY: Double, camera: CameraPosition?) -> Int? {
        guard let camera else { return nil }
        let span = camera.floorY - camera.y100
        guard span > 0 else { return nil }
        let cm = (camera.floorY - headY) * 100 / span
        let mm = Int((cm * 2).rounded()) * 5
        return HeightFormatter.isValid(mm) ? mm : nil
    }

    /// The value the height field starts with: the estimate, else the member's last height,
    /// else empty (first record without an estimate; the user must enter it).
    static func initialDraft(estimateMM: Int?, lastMM: Int?) -> (mm: Int?, fromEstimate: Bool) {
        if let estimateMM { return (estimateMM, true) }
        return (lastMM, false)
    }
}
