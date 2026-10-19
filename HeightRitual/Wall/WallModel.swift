import SwiftUI

/// Everything the wall image needs for one frame, as a value taken from AppState.
/// Positions are in real centimetres (millimetres for heights); `WallGeometry` turns them into points.
struct WallModel: Equatable {
    enum Kind: Equatable {
        /// Faint ruler: Home and screens that leave the wall unchanged.
        case idle
        /// Pencil marks, a life-size figure, captions.
        case marks
        /// M2 ready: foot marks and the outline where to stand.
        case footGuide
        /// Countdown and filming: dark, only the number.
        case dark
        /// S2: centimetre ruler for fitting to a tape on the wall.
        case ruler
        /// S3: two bright lines at 0 and 100 cm for the camera position.
        case cameraLines
        /// Home, the member menu and adding a member: the wall shows the screen itself
        /// (`WallScreen`), driven by the controller.
        case screen
        /// S list: the settings as tiles in two columns, Setup guide as a pill beside the title. Only shown; the
        /// settings are changed on the phone.
        case settingsMenu
        /// S4 Units: the two units, the controller's choice outlined. Only Units has a page so far.
        case settingsUnits
    }

    struct Mark: Equatable {
        var label: String
        var heightMM: Int
        var selected: Bool
    }

    struct Figure: Equatable {
        var heightMM: Int
        var posterFile: String?
        /// With a clip, the wall player's picture stands here; without, a soft outline.
        var hasClip = false
        var bodyRatio: Double?
        var floorRatio: Double?
        /// Clip width / height.
        var aspect: Double?
        /// The clip as filmed is opaque: marks and captions are drawn again on top of it.
        var opaque = false
    }

    var kind: Kind = .idle
    var calibration = Calibration()
    var accent: Color = Palette.color(0)
    var marks: [Mark] = []
    var figure: Figure?
    var caption: String?
    /// False where the wall's screen draws its own text over the picture (Lookback).
    var showsText = true
    /// Large name or message near the top of the picture.
    var headline: String?
    /// Dashed coral line of a record being made.
    var liveMM: Int?
    var liveLabel: String?
    /// Countdown number or seconds left while filming.
    var bigNumber: Int?
    /// Height of the standing outline on the foot guide.
    var guideMM: Int?
    var fitValue: FitValue?
    var unit: HeightUnit = .cm
}

extension AppState {
    var wallModel: WallModel {
        var model = WallModel()
        model.calibration = settings.wall
        model.unit = settings.unit
        let unit = settings.unit

        func marks(of memberID: UUID?, selecting index: Int?) -> [WallModel.Mark] {
            guard let memberID else { return [] }
            return store.records(for: memberID).enumerated().map { i, record in
                WallModel.Mark(label: "\(record.date.monthYear)   \(HeightFormatter.text(record.heightMM, unit: unit))",
                               heightMM: record.heightMM,
                               selected: i == index)
            }
        }

        func showMemoryWall() {
            model.kind = .marks
            model.showsText = false
            model.accent = Palette.color(currentMember?.colorIndex ?? 0)
            model.marks = marks(of: memberID, selecting: recordIndex)
            if let record = selectedRecord, let member = currentMember {
                let raw = settings.showBackground && record.rawVideoFile != nil || record.videoFile == nil
                model.figure = .init(heightMM: record.heightMM, posterFile: record.posterFile,
                                     hasClip: clipURL(record) != nil,
                                     bodyRatio: raw ? record.rawBodyRatio : record.bodyRatio,
                                     floorRatio: raw ? record.rawFloorRatio : record.floorRatio,
                                     aspect: raw ? (record.rawAspect ?? 9.0 / 16.0) : record.clipAspect,
                                     opaque: raw)
                model.caption = "\(member.name), \(record.date.monthYear), \(HeightFormatter.text(record.heightMM, unit: unit))"
            } else {
                model.headline = L("No records yet")
            }
        }

        switch route {
        case .memberEdit, .wizard(.welcome), .wizard(.permissions):
            model.kind = .idle

        case .settings(.fitToWall), .wizard(.fitToWall):
            model.kind = .ruler
            model.fitValue = fitValue

        case .settings(.cameraPosition), .wizard(.cameraPosition):
            model.kind = .cameraLines

        case .settings(.list):
            model.kind = .settingsMenu

        case .settings(.units):
            model.kind = .settingsUnits

        case .settings:
            model.kind = .idle

        case .home, .memberMenu, .addMember, .tutorial:
            model.kind = .screen

        case .makeFilm:
            // Ready and filming: the life-size outline to stand in; the wall's own screen
            // (title, Record, time left) is laid over it (`WallFilmOverlay`).
            model.kind = .footGuide
            model.accent = Theme.guide
            model.guideMM = FootGuide.outlineMM(lastMM: memberID.flatMap(store.lastRecord)?.heightMM)

        case .makeHeight, .makeSaved:
            model.kind = .screen

        case .memoryWall, .record:
            showMemoryWall()
        }
        return model
    }
}
