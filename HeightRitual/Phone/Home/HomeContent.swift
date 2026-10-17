import SwiftUI

/// H: the wheel of member cards, on the phone or the wall (Figma 197:2107, 214:527, 223:1332,
/// 223:1387). The card in the middle is the highlighted one; its neighbours lean on the ring.
/// Knob and Left / Right turn the wheel; Confirm opens the card. The Add card comes last.
struct HomeContent: View {
    let surface: Surface
    @Environment(AppState.self) private var state

    var body: some View {
        let members = state.store.members
        let empty = members.isEmpty
        let highlight = state.highlight
        let w = surface.canvas.width

        ZStack(alignment: .topLeading) {
            ring
            pointer

            ForEach(0..<state.homeCardCount, id: \.self) { index in
                let member = members.indices.contains(index) ? members[index] : nil
                WheelCard(surface: surface, member: member, offset: index - highlight,
                          addLabel: empty && surface == .phone ? Text("Add member") : Text("Add"),
                          squeeze: state.confirmCount, pressable: state.route == .home)
                    .onTapGesture {
                        guard surface == .phone else { return }
                        if index == highlight { state.openTile(index) } else { state.moveHighlight(by: index - highlight) }
                    }
            }

            if !empty || surface == .wall {
                arrows(atStart: highlight == 0, atEnd: highlight >= state.homeCardCount - 1)
            }

            // Under the member menu its own heading takes this place.
            if !state.showsMemberMenu {
                ScreenHeading(surface: surface, title: title(empty), subtitle: subtitle(empty))
            }

            if surface == .wall && !state.showsMemberMenu {
                bottomHint(empty: empty)
                    .position(x: w / 2, y: 947)
            }
        }
        .frame(width: surface.canvas.width, height: surface.canvas.height)
        .contentShape(Rectangle())
        .gesture(swipe)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: highlight)
    }

    // MARK: Parts

    private var ring: some View {
        let outer = surface.v(687.6, 922.3), inner = surface.v(555.2, 744.7)
        let outerCenter = surface.p(CGPoint(x: 201, y: 817.8), CGPoint(x: 304, y: 1097))
        let innerCenter = surface.p(CGPoint(x: 201, y: 900.4), CGPoint(x: 304, y: 1207.8))
        return ZStack(alignment: .topLeading) {
            Circle().fill(Theme.track).frame(width: outer, height: outer).position(outerCenter)
            Circle().fill(Theme.paper).frame(width: inner, height: inner).position(innerCenter)
        }
    }

    private var pointer: some View {
        let top = surface.v(523.9, 721.5), length = surface.v(58.5, 77.5)
        return Capsule()
            .fill(Theme.ink)
            .frame(width: surface.v(5, 6.6), height: length)
            .position(x: surface.canvas.width / 2, y: top + length / 2)
    }

    private func arrows(atStart: Bool, atEnd: Bool) -> some View {
        let size = surface.v(58.9, 98)
        let y = surface.v(358.2, 491)
        let left = surface.v(71.2, 111), right = surface.v(330.8, 493.5)
        return ZStack(alignment: .topLeading) {
            arrow(.left, size: size, enabled: !atStart) { state.moveHighlight(by: -1) }
                .position(x: left, y: y)
            arrow(.right, size: size, enabled: !atEnd) { state.moveHighlight(by: 1) }
                .position(x: right, y: y)
        }
    }

    @ViewBuilder
    private func arrow(_ glyph: ControlIcon.Glyph, size: CGFloat, enabled: Bool,
                       action: @escaping () -> Void) -> some View {
        if surface == .phone {
            Button(action: action) {
                ControlIcon(glyph: glyph, size: size, isEnabled: enabled)
            }
            .buttonStyle(PressStyle())
            .disabled(!enabled)
            .accessibilityLabel(glyph == .left ? Text("Previous") : Text("Next"))
        } else {
            ControlIcon(glyph: glyph, size: size, isEnabled: enabled)
        }
    }

    @ViewBuilder
    private func bottomHint(empty: Bool) -> some View {
        if empty && !state.confirmFlash {
            Text("Press \(inlineIcon(.confirm, size: 30)) to add")
                .font(Theme.subtitle(30))
                .foregroundStyle(Theme.hint)
        } else {
            ConfirmCheck(size: 100, confirmed: state.confirmFlash)
        }
    }

    private func title(_ empty: Bool) -> Text {
        empty ? Text("Let's start with your family") : Text("Choose a family member")
    }

    private func subtitle(_ empty: Bool) -> Text {
        if empty { return Text("Add someone you want to measure") }
        if surface == .phone { return Text("Swipe to browse, then tap to start") }
        let size: CGFloat = 33.3
        return Text("Turn the knob or press \(inlineIcon(.left, size: size)) \(inlineIcon(.right, size: size)),\nthen press \(inlineIcon(.confirm, size: size))")
    }

    /// Phone only: a sideways swipe turns the wheel by one card.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard surface == .phone, abs(value.translation.width) > 40,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                state.moveHighlight(by: value.translation.width < 0 ? 1 : -1)
            }
    }
}

/// One card on the wheel, placed by its distance from the middle (0 = the highlighted card).
private struct WheelCard: View {
    let surface: Surface
    let member: Member?
    let offset: Int
    let addLabel: Text
    let squeeze: Int
    /// Only on Home itself: under the member menu, Confirm belongs to the menu's cards.
    let pressable: Bool

    var body: some View {
        let center = offset == 0
        let side = Double(offset.signum())
        let far = abs(offset) >= 2

        // Every card is drawn at the middle card's size and scaled down at the sides, so the name,
        // its band, the corners and the border all shrink together while the wheel turns.
        let size = surface.s(CGSize(width: 172, height: 258), CGSize(width: 228, height: 342))
        let sideScale = surface.v(84.0 / 172, 154.0 / 228)
        let mid = surface.p(CGPoint(x: 201, y: 367.6), CGPoint(x: 304, y: 514.7))
        let step = surface.p(CGPoint(x: 163.9, y: 210.6), CGPoint(x: 272, y: 176.7))
        let reach = far ? 1.8 : 1.0
        let position = CGPoint(x: mid.x + side * step.x * reach, y: mid.y + (center ? 0 : step.y * (far ? 1.5 : 1)))

        CardFace(surface: surface, member: member, size: size, isCenter: center, addLabel: addLabel)
            .confirmSqueeze(squeeze, active: center && pressable)
            .scaleEffect(center ? 1 : sideScale)
            .rotationEffect(.degrees(side * (far ? 55 : 30)))
            .position(position)
            .opacity(far ? 0 : 1)
            .zIndex(center ? 2 : 1)
    }
}

/// The face of a card: a member (picture area and name band) or Add.
struct CardFace: View {
    @Environment(AppState.self) private var state
    let surface: Surface
    let member: Member?
    let size: CGSize
    let isCenter: Bool
    var addLabel: Text = Text("Add")

    var body: some View {
        let scale = size.height / surface.v(258, 342)
        let radius = surface.v(20, 26.5) * scale

        ZStack(alignment: .bottom) {
            if let member {
                // The member's own colour, or their newest photo (`Member.card`).
                RoundedRectangle(cornerRadius: radius).fill(Palette.color(member.colorIndex))
                memberPhoto(member)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                Rectangle()
                    .fill(Theme.paper)
                    .frame(height: size.height * 0.27)
                    .overlay {
                        Text(verbatim: member.name)
                            .font(Theme.cardName(surface.v(30, 39.8) * scale))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 6)
                    }
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
            } else {
                RoundedRectangle(cornerRadius: radius).fill(Theme.card)
                VStack(spacing: 12 * scale) {
                    Circle()
                        .fill(Theme.paper)
                        .frame(width: 70 * scale, height: 70 * scale)
                        .overlay {
                            Image(systemName: "person.fill.badge.plus")
                                .font(.system(size: 26 * scale, weight: .medium))
                                .foregroundStyle(Theme.iconInk)
                        }
                    addLabel
                        .font(Theme.label(22 * scale))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(Theme.ink, lineWidth: surface.v(5, 6.6))
                .opacity(isCenter ? 1 : 0)
        }
        .shadow(color: .black.opacity(isCenter ? 0.1 : 0), radius: surface.v(16, 21))
    }

    @ViewBuilder
    private func memberPhoto(_ member: Member) -> some View {
        if member.card == .photo,
           let image = state.store.latestPhotoURL(for: member.id).flatMap({ UIImage(contentsOfFile: $0.path) }) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size.width, height: size.height)
        }
    }
}
