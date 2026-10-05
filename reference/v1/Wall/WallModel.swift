import SwiftUI
import UIKit

/// Everything the projector needs for one frame, taken from AppState on the main actor.
struct WallModel {
    struct Mark {
        let label: String
        let heightCM: Double
        let selected: Bool
    }

    var screen: Screen = .view
    var calibration = Calibration()
    var accent: Color = Palette.color(0)
    var marks: [Mark] = []
    /// Life-size figure: the cut-out photo, or a soft outline when the record has no photo.
    var figureHeightCM: Double?
    var figurePhoto: UIImage?
    var caption: String?
    var headline: String?
    var liveHeightCM: Double?
    var liveCaption: String?
    var countdown: Int?
    var calibrationParam: CalibrationParam = .floor
}

extension AppState {
    var wallModel: WallModel {
        var model = WallModel()
        model.screen = screen
        model.calibration = calibration
        model.calibrationParam = calibrationParam
        model.accent = Palette.color(currentChild?.colorIndex ?? 0)

        let records = currentRecords
        let name = currentChild?.name ?? ""

        func marks(selecting index: Int?) -> [WallModel.Mark] {
            records.enumerated().map { i, record in
                WallModel.Mark(label: "\(record.date.yearOnly)   \(Int(record.heightCM.rounded())) cm",
                               heightCM: record.heightCM,
                               selected: i == index)
            }
        }

        switch screen {
        case .view, .playback:
            model.marks = marks(selecting: recordIndex)
            if let record = selectedRecord {
                model.figureHeightCM = record.heightCM
                model.figurePhoto = store.image(for: record)
                model.caption = "\(name), \(record.date.monthYear)"
            } else {
                model.headline = name.isEmpty ? "No records yet" : "\(name) has no records yet"
            }

        case .selectChild:
            model.marks = marks(selecting: nil)
            model.headline = name

        case .enterHeight:
            model.marks = marks(selecting: nil)
            model.liveHeightCM = draftHeightCM
            if let last = lastRecord {
                model.liveCaption = "\((draftHeightCM - last.heightCM).signedCM) since \(last.date.yearOnly)"
            }

        case .capture:
            // Keep the wall dark so the projector does not shine into the child's eyes.
            model.liveHeightCM = draftHeightCM
            model.countdown = countdown

        case .review:
            model.marks = marks(selecting: nil)
            model.liveHeightCM = draftHeightCM
            model.figureHeightCM = draftHeightCM
            model.figurePhoto = cutout
            model.caption = "\(name), today"

        case .calibrate:
            break
        }
        return model
    }
}
