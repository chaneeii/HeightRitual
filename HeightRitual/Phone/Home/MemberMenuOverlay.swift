import SwiftUI

/// H1: Home darkens and offers Record or Lookback for the chosen member (Figma 215:723, 223:1538).
/// On the wall the highlighted choice has a thick border and the cursor; Left / Right move it,
/// Confirm opens it, Cancel goes back to the wheel. On the phone a tap opens a choice.
struct MemberMenuOverlay: View {
    let surface: Surface
    @Environment(AppState.self) private var state

    var body: some View {
        let name = state.currentMember?.name ?? ""
        let choice = state.menuChoice
        let w = surface.canvas.width

        ZStack(alignment: .topLeading) {
            Theme.scrim
                .frame(width: surface.canvas.width, height: surface.canvas.height)
                .onTapGesture { if surface == .phone { state.closeMemberMenu() } }

            ScreenHeading(surface: surface, title: Text(verbatim: name), subtitle: subtitle,
                          onDark: true, top: surface.v(165, 153))

            choiceCard(.record, selected: choice == .record)
                .position(surface.p(CGPoint(x: 124.4, y: 414), CGPoint(x: 177.8, y: 538)))
            choiceCard(.lookback, selected: choice == .lookback)
                .position(surface.p(CGPoint(x: 287, y: 414), CGPoint(x: 430.2, y: 538)))

            if surface == .wall {
                let cardSize = CGSize(width: 229, height: 320)
                let center = choice == .record ? CGPoint(x: 177.8, y: 538) : CGPoint(x: 430.2, y: 538)
                CursorView(size: 65, trigger: choice)
                    .position(x: center.x + cardSize.width / 2 - 54 + 32, y: center.y + cardSize.height / 2 - 33 + 32)

                caption(choice, name: name)
                    .font(Theme.subtitle(33.3))
                    .foregroundStyle(Theme.paper)
                    .position(x: w / 2, y: 766.7)
                    .id(choice)
                    .transition(.opacity)

                ConfirmCheck(size: 120, confirmed: state.confirmFlash)
                    .position(x: w / 2, y: 963)

                ControlIcon(glyph: .back, size: 75.4)
                    .foregroundStyle(Theme.paper)
                    .position(x: 24 + 37.7, y: 28 + 37.7)
            } else {
                PhoneAppBar(back: .filled, onDark: true, onBack: { state.closeMemberMenu() },
                            onGear: { state.openMemberEdit(state.currentMember?.id) },
                            gearLabel: Text("Edit \(name)"))
            }
        }
        .frame(width: surface.canvas.width, height: surface.canvas.height)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: choice)
    }

    private var subtitle: Text {
        if surface == .phone { return Text("Tap to choose") }
        let size: CGFloat = 33.3
        return Text("Press \(inlineIcon(.left, size: size)) or \(inlineIcon(.right, size: size)) to choose, then \(inlineIcon(.confirm, size: size))")
    }

    private func caption(_ choice: MemberAction, name: String) -> Text {
        choice == .record ? Text("Record today's height") : Text("Watch \(name) grow")
    }

    @ViewBuilder
    private func choiceCard(_ action: MemberAction, selected: Bool) -> some View {
        let size = surface.s(CGSize(width: 135, height: 188.6), CGSize(width: 229, height: 320))
        let radius = surface.v(20, 34)
        let face = VStack(spacing: surface.v(18, 30.5)) {
            Circle()
                .fill(Theme.paper)
                .frame(width: surface.v(82, 139), height: surface.v(82, 139))
                .overlay {
                    Image(systemName: action == .record ? "video.fill" : "play.rectangle.fill")
                        .font(.system(size: surface.v(30, 51), weight: .medium))
                        .foregroundStyle(Theme.iconInk)
                }
            Text(action == .record ? "Record" : "Lookback")
                .font(Theme.label(surface.v(20, 34)))
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size.width, height: size.height)
        .background(Theme.choice, in: RoundedRectangle(cornerRadius: radius))
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(Theme.accent, lineWidth: surface == .wall && selected ? 8.5 : 0)
        }
        .confirmSqueeze(state.confirmCount, active: selected)

        if surface == .phone {
            Button { state.chooseMenu(action) } label: { face }
                .buttonStyle(PressStyle())
        } else {
            face
        }
    }
}
