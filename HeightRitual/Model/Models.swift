import Foundation
import SwiftUI

/// A person whose height the family records. Not only children: anyone in the family can stand at the wall.
struct Member: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var colorIndex: Int
    /// Profile photo in Documents/media; nil shows the first letter in the member's colour.
    var photoFile: String?
    /// What the member's card on Home shows. Optional so older saved members still load.
    var cardStyle: CardStyle?

    /// The latest photo by default, so a new record shows on the card at once.
    var card: CardStyle { cardStyle ?? .photo }

    /// "N" for Nora: the avatar without a photo.
    var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

/// The picture area of a member's card: their colour, or the newest photo from a record
/// (the colour until there is one).
enum CardStyle: String, Codable, CaseIterable {
    case colour
    case photo
}

/// What A1 does with the profile photo on Save.
enum PhotoChange: Equatable {
    case keep
    case set(Data)
    case remove
}

/// One measurement: who, when, how tall, and the cut-out clip filmed at that moment.
struct GrowthRecord: Identifiable, Codable, Hashable {
    enum HeightSource: String, Codable {
        case estimated, edited, sample
    }

    var id = UUID()
    var memberID: UUID
    var date: Date
    var heightMM: Int
    var heightSource: HeightSource
    /// File names in Documents/media. Nil for sample records, which are drawn as soft outlines.
    var videoFile: String?
    var posterFile: String?
    var hasSound = false
    /// Body height / clip height, and feet above the clip's bottom edge / clip height.
    var bodyRatio: Double?
    var floorRatio: Double?
    /// The clip as filmed, with its background, and the same layout numbers for it.
    var rawVideoFile: String?
    var rawBodyRatio: Double?
    var rawFloorRatio: Double?
    /// Width / height of the cut-out and of the raw clip; clip length in seconds.
    var clipAspect: Double?
    var rawAspect: Double?
    var duration: Double?
}

enum Palette {
    static let memberColors: [Color] = [
        Color(red: 0.91, green: 0.69, blue: 0.29),
        Color(red: 0.49, green: 0.79, blue: 0.56),
        Color(red: 0.55, green: 0.70, blue: 0.95),
        Color(red: 0.91, green: 0.54, blue: 0.36),
        Color(red: 0.78, green: 0.58, blue: 0.90),
        Color(red: 0.40, green: 0.80, blue: 0.82),
    ]

    static func color(_ index: Int) -> Color {
        let n = memberColors.count
        return memberColors[((index % n) + n) % n]
    }
}

extension Date {
    /// "Aug 2025", in the app's language.
    var monthYear: String {
        formatted(.dateTime.month(.abbreviated).year().locale(.english))
    }
}
