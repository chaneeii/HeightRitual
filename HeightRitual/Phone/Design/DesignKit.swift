import SwiftUI
import UIKit

/// Draws a Figma frame (`surface.canvas`) scaled to fit the space and centred. Children are placed
/// in the frame's own coordinates with `.position`, so the layouts can follow Figma exactly on the
/// phone and on the 608 x 1080 wall strip alike.
struct DesignCanvas<Content: View>: View {
    let surface: Surface
    var background: Color = Theme.paper
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let canvas = surface.canvas
            let scale = min(geo.size.width / canvas.width, geo.size.height / canvas.height)
            ZStack(alignment: .topLeading) {
                content()
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(background)
    }
}

/// Buttons shrink a little while held: the press animation of the redesign.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension View {
    /// The same press on the wall, where there is no finger: a short squeeze whenever Confirm
    /// is used (`AppState.confirmCount`).
    func confirmSqueeze(_ trigger: Int, active: Bool = true) -> some View {
        keyframeAnimator(initialValue: 1.0, trigger: trigger) { content, scale in
            content.scaleEffect(active ? scale : 1)
        } keyframes: { _ in
            SpringKeyframe(0.92, duration: 0.1)
            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
        }
    }
}

/// The pointer that marks the selection on the wall. It pops each time the selection moves.
struct CursorView: View {
    var size: CGFloat
    /// Changes whenever the selection moves.
    var trigger: AnyHashable

    var body: some View {
        Image("Cursor")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: 1.0, trigger: trigger) { content, scale in
                content.scaleEffect(scale, anchor: .topLeading)
            } keyframes: { _ in
                SpringKeyframe(1.3, duration: 0.12)
                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
            }
            .accessibilityHidden(true)
    }
}

/// The round check at the bottom of the wall: gray until Confirm, then green with a pop.
struct ConfirmCheck: View {
    var size: CGFloat
    var confirmed: Bool

    var body: some View {
        ZStack {
            ControlIcon(glyph: .confirmOutline, size: size, isEnabled: false)
                .opacity(confirmed ? 0 : 1)
            ControlIcon(glyph: .confirm, size: size, confirmed: true)
                .scaleEffect(confirmed ? 1 : 0.4)
                .opacity(confirmed ? 1 : 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: confirmed)
    }
}

/// A controller icon inside running text ("then press ✓"), at the text's size and colour.
/// An asset image in `Text` would otherwise keep its 100 pt drawing size.
func inlineIcon(_ glyph: ControlIcon.Glyph, size: CGFloat) -> Text {
    let side = size * 0.9
    let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
        UIImage(named: glyph.rawValue)?.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
    }.withRenderingMode(.alwaysTemplate)
    return Text(Image(uiImage: image)).baselineOffset(-side * 0.14)
}

/// Debug builds only: shows the wall picture on the phone, so the wall's screens can be checked
/// without a projector. Sits left of the Settings button on every page.
struct DebugWallButton: View {
    var size: CGFloat = 26.8
    var color: Color = Theme.ink
    @Environment(AppState.self) private var state

    var body: some View {
        #if DEBUG
        Button {
            state.debugShowsWall.toggle()
        } label: {
            Image(systemName: state.debugShowsWall ? "iphone" : "videoprojector")
                .font(.system(size: size * 0.75, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: max(size, 44), height: max(size, 44))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(Text(verbatim: "Debug: show the wall"))
        #endif
    }
}

/// The phone's own bar in the redesign: optional back on the left, debug and Settings on the right.
/// Drawn inside a phone `DesignCanvas`, at Figma's position under the status bar.
struct PhoneAppBar: View {
    enum Back { case none, arrow, filled }
    var back: Back = .none
    var onDark = false
    var onBack: () -> Void = {}
    /// The gear opens app Settings unless a screen gives it its own job (the member menu: edit
    /// this member).
    var onGear: (() -> Void)?
    var gearLabel: Text = Text("Settings")
    @Environment(AppState.self) private var state

    var body: some View {
        let color = onDark ? Theme.paper : Theme.ink
        HStack(spacing: 8) {
            switch back {
            case .none:
                EmptyView()
            case .arrow:
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(color)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Back")
            case .filled:
                Button(action: onBack) {
                    ControlIcon(glyph: .back, size: 42.4)
                        .foregroundStyle(color)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Back")
            }
            Spacer()
            DebugWallButton(color: color)
            Button {
                if let onGear { onGear() } else { state.openSettings() }
            } label: {
                Image("Gear")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(gearLabel)
        }
        .padding(.horizontal, 14)
        .frame(width: Surface.phone.canvas.width, height: 44)
        .position(x: Surface.phone.canvas.width / 2, y: 61.5 + 22 + 6)
    }
}

/// Title and description at the top of a redesigned screen.
struct ScreenHeading: View {
    let surface: Surface
    let title: Text
    let subtitle: Text
    var onDark = false
    var top: CGFloat = 121

    var body: some View {
        VStack(spacing: surface.v(4, 8)) {
            title
                .font(Theme.title(surface.v(28, 42.4)))
            subtitle
                .font(Theme.subtitle(surface.v(22, 33.3)))
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(onDark ? Theme.paper : Theme.ink)
        .frame(width: surface.canvas.width - 24)
        .fixedSize(horizontal: false, vertical: true)
        .position(x: surface.canvas.width / 2, y: top)
        .alignmentGuide(VerticalAlignment.top) { _ in 0 }
        .offset(y: surface.v(40, 62))
    }
}
