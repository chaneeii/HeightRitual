import Foundation

/// The only place that turns stored millimetres into text or steps them,
/// so the unit setting applies to every height on the phone and the wall.
enum HeightFormatter {
    static let minMM = 400
    static let maxMM = 2200
    /// Starting value when the knob is turned on an empty height field.
    static let emptyFieldStartMM = 1000

    private static let mmPerInch = 25.4

    /// "121.0 cm" or "3 ft 11 3/4 in".
    static func text(_ mm: Int, unit: HeightUnit) -> String {
        switch unit {
        case .cm:
            return String(format: "%.1f cm", Double(mm) / 10)
        case .ftin:
            let quarters = Int((Double(mm) / mmPerInch * 4).rounded())
            let feet = quarters / 48
            let rest = quarters % 48
            let inches = rest / 4
            let fraction = ["", " 1/4", " 1/2", " 3/4"][rest % 4]
            return "\(feet) ft \(inches)\(fraction) in"
        }
    }

    /// A height as a large number and a small unit: ("121.0", "cm"); ft and in stay in one piece.
    static func parts(_ mm: Int, unit: HeightUnit) -> (number: String, unit: String?) {
        switch unit {
        case .cm: return (String(format: "%.1f", Double(mm) / 10), "cm")
        case .ftin: return (text(mm, unit: .ftin), nil)
        }
    }

    /// Growth between two records, "+5.0 cm" or "+2 in".
    static func difference(_ mm: Int, unit: HeightUnit) -> String {
        let sign = mm < 0 ? "-" : "+"
        switch unit {
        case .cm:
            return sign + String(format: "%.1f cm", Double(abs(mm)) / 10)
        case .ftin:
            let quarters = Int((Double(abs(mm)) / mmPerInch * 4).rounded())
            let whole = quarters / 4
            let fraction = ["", " 1/4", " 1/2", " 3/4"][quarters % 4]
            return "\(sign)\(whole)\(fraction) in"
        }
    }

    /// Moves a height by knob steps (fine: 0.5 cm or 1/4 in) or by Left / Right steps
    /// (coarse: 1 cm or 1 in). The result snaps to the unit's grid and stays in 40 to 220 cm.
    static func step(_ mm: Int, by steps: Int, unit: HeightUnit, coarse: Bool) -> Int {
        let result: Int
        switch unit {
        case .cm:
            let halfCM = Int((Double(mm) / 5).rounded()) + steps * (coarse ? 2 : 1)
            result = halfCM * 5
        case .ftin:
            let quarters = Int((Double(mm) / mmPerInch * 4).rounded()) + steps * (coarse ? 4 : 1)
            result = Int((Double(quarters) * mmPerInch / 4).rounded())
        }
        return clamp(result)
    }

    static func clamp(_ mm: Int) -> Int { min(max(mm, minMM), maxMM) }

    static func isValid(_ mm: Int) -> Bool { (minMM...maxMM).contains(mm) }
}
