import SwiftUI

/// Colours and type for the redesign (Figma "Ritual", Oct 2026). Black and white for now: the real
/// palette and fonts come later, so every screen takes them from here and nothing else.
enum Theme {
    // MARK: Colours

    static let ink = Color.black
    /// The point colour, chosen in Settings (black by default): selection borders, the main
    /// button, the dial's needle, the filming bar, the saved check, the cursor. Read through the
    /// settings so every screen redraws when it changes.
    @MainActor static var accent: Color {
        pointColour(AppState.shared.settings.accentIndex)
    }

    /// The one place the point colour is worked out, for every border and pointer in the app.
    /// `onDark`: on a black background (the settings pages on the wall) Black is drawn white.
    static func pointColour(_ accentIndex: Int?, onDark: Bool = false) -> Color {
        accentIndex.map(Palette.color) ?? (onDark ? .white : ink)
    }
    static let paper = Color.white
    /// The ring of the Home wheel.
    static let track = Color(white: 0xE0 / 255)
    /// Cards that are not a member: Add, the menu choices, keys of the letter wheel.
    static let card = Color(white: 0xF3 / 255)
    static let key = Color(white: 0xEE / 255)
    static let field = Color(white: 0xF1 / 255)
    static let choice = Color(white: 0xEC / 255)
    /// Icons inside the white circles on cards.
    static let iconInk = Color(white: 0x49 / 255)
    /// Instead of the member's colour until the palette is decided.
    static let memberCard = Color(white: 0xD9 / 255)
    /// Darkens Home under the member menu.
    static let scrim = Color.black.opacity(0.6)
    static let hint = Color(white: 0x6B / 255)
    /// The text cursor in the name field.
    @MainActor static var caret: Color { accent }
    /// The selection on the member menu (Record or Lookback): a blue of its own.
    static let menuHighlight = Palette.color(2)
    /// The outline to stand in and the foot marks, on the camera picture and the wall.
    static let guide = Color(white: 0.88)
    /// Record (the one coloured control: it films).
    static let record = Color(red: 0.98, green: 0.24, blue: 0.27)
    /// The bar that fills while filming.
    @MainActor static var progress: Color { accent }
    static let progressTrack = Color(white: 0xCC / 255)
    static let dialTick = Color(white: 0.45)
    @MainActor static var dialNeedle: Color { accent }
    /// Secondary buttons (Retake, Return to home).
    static let secondaryButton = Color(white: 0xF2 / 255)
    /// Secondary buttons on the wall, white text.
    static let wallSecondaryButton = Color(white: 0xB3 / 255)
    /// The controller box as drawn on the onboarding, in the colours of the real buttons.
    static let controllerBody = Color(white: 0xF1 / 255)
    static let controllerOff = Color(white: 0xD9 / 255)
    static let controllerBack = Color(red: 0.94, green: 0.42, blue: 0.18)
    static let controllerArrow = Color(red: 0.50, green: 0.70, blue: 0.98)
    static let controllerConfirm = ControlIcon.confirmGreen
    /// Delete on the letter wheel.
    static let destructive = Color(red: 0.90, green: 0.18, blue: 0.16)
    /// Save on the letter wheel, and a confirmed check.
    static let success = ControlIcon.confirmGreen
    /// Settings on the projector: light gray panels on the white wall, black text; the choice is
    /// outlined in black, Back is a black pill (as on Home).
    static let wallPanel = Color(white: 0.95)
    static let wallPanelSelected = Color(white: 0.91)
    static let wallPill = ink

    // MARK: Type

    /// Screen titles: Black Han Sans (bundled, SIL Open Font License, Resources/Fonts).
    static func title(_ size: CGFloat) -> Font { .custom("BlackHanSans-Regular", fixedSize: size) }
    /// The line under a title: regular and a little smaller than the old light face. SF Compact
    /// Text may not be bundled (Apple's font licence), so the system text face stands in for it.
    static func subtitle(_ size: CGFloat) -> Font { .system(size: size * 0.86, weight: .regular) }
    /// Names on the Home wheel's cards: Black Han Sans, like the titles.
    static func cardName(_ size: CGFloat) -> Font { .custom("BlackHanSans-Regular", fixedSize: size) }
    /// Record and Lookback on the member menu's cards.
    static func choiceLabel(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func label(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    /// The line under a choice ("Record today's height", "Watch Nora grow"): the thin face.
    static func note(_ size: CGFloat) -> Font { .system(size: size, weight: .light) }
    static func key(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
    static func field(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
}

/// Where a screen is drawn: on the phone (touch, its own buttons and copy) or on the wall
/// (608 x 1080 projector strip, driven by the controller, with a cursor).
enum Surface {
    case phone
    case wall

    /// The Figma frame each layout below is measured in.
    var canvas: CGSize {
        self == .phone ? CGSize(width: 402, height: 874) : CGSize(width: 608, height: 1080)
    }

    var isWall: Bool { self == .wall }

    /// Picks the phone or the wall measurement.
    func v(_ phone: CGFloat, _ wall: CGFloat) -> CGFloat { self == .phone ? phone : wall }
    func p(_ phone: CGPoint, _ wall: CGPoint) -> CGPoint { self == .phone ? phone : wall }
    func s(_ phone: CGSize, _ wall: CGSize) -> CGSize { self == .phone ? phone : wall }
}
