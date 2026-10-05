import Foundation
import SwiftUI

struct Child: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var colorIndex: Int
}

/// One measurement: who, when, how tall, and the cut-out photo taken at that moment.
struct GrowthRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var childID: UUID
    var date: Date
    var heightMM: Int
    /// PNG file name in Documents/photos. Nil for sample data without a photo.
    var photoFile: String?

    var heightCM: Double { Double(heightMM) / 10 }
}

enum Palette {
    static let childColors: [Color] = [
        Color(red: 0.91, green: 0.69, blue: 0.29),
        Color(red: 0.49, green: 0.79, blue: 0.56),
        Color(red: 0.55, green: 0.70, blue: 0.95),
        Color(red: 0.91, green: 0.54, blue: 0.36),
    ]

    static func color(_ index: Int) -> Color {
        let n = childColors.count
        return childColors[((index % n) + n) % n]
    }
}

extension Date {
    var monthYear: String { formatted(.dateTime.month(.abbreviated).year()) }
    var yearOnly: String { formatted(.dateTime.year()) }
}

extension Double {
    var cmText: String { String(format: "%.1f cm", self) }
    var signedCM: String { String(format: "%+.1f cm", self) }
}
