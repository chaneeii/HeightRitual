import SwiftUI

/// The buttons on the controller box, as drawn in Figma ("Controller Icons"). Every screen that
/// names a control uses these, not SF Symbols or words alone.
///
/// Colour follows the background through the current foreground style: black on light screens,
/// white on dark ones and on strong colours (set `.foregroundStyle(.white)` there). Gray means the
/// control does nothing on this screen: put the icon in a disabled view or pass `isEnabled: false`.
struct ControlIcon: View {
    enum Glyph: String, CaseIterable {
        case back = "ControlBackFill"            // Cancel / Back, filled
        case backOutline = "ControlBack"         // Cancel / Back, outline
        case confirm = "ControlCheck"            // Confirm (the round button), filled
        case confirmOutline = "ControlCheckOutline"
        case left = "ControlLeft"
        case right = "ControlRight"
        case knob = "ControlKnob"
    }

    let glyph: Glyph
    var size: CGFloat = 32
    /// Confirm in green with a white tick, for a choice that has just been made.
    var confirmed = false
    var isEnabled = true

    @Environment(\.isEnabled) private var environmentEnabled

    static let disabledFill = Color(red: 0xCE / 255, green: 0xCE / 255, blue: 0xCE / 255)
    static let disabledLine = Color(red: 0xDF / 255, green: 0xDF / 255, blue: 0xDF / 255)
    static let confirmGreen = Color(red: 0x00 / 255, green: 0xCB / 255, blue: 0x49 / 255)

    var body: some View {
        Group {
            if !(isEnabled && environmentEnabled) {
                image.foregroundStyle(glyph == .confirmOutline ? Self.disabledLine : Self.disabledFill)
            } else if confirmed && glyph == .confirm {
                // The tick is cut out of the circle; a white disc behind it keeps it white anywhere.
                ZStack {
                    Circle().fill(.white).padding(size * 0.25)
                    image.foregroundStyle(Self.confirmGreen)
                }
            } else {
                image
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var image: some View {
        Image(glyph.rawValue).resizable().scaledToFit()
    }
}

#Preview("Controller icons") {
    let all = ControlIcon.Glyph.allCases
    VStack(spacing: 24) {
        HStack { ForEach(all, id: \.self) { ControlIcon(glyph: $0) } }
        HStack { ForEach(all, id: \.self) { ControlIcon(glyph: $0) } }
            .foregroundStyle(.white)
            .padding()
            .background(.black)
        HStack { ForEach(all, id: \.self) { ControlIcon(glyph: $0, isEnabled: false) } }
        ControlIcon(glyph: .confirm, confirmed: true)
    }
    .padding()
}
