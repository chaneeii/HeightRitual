import SwiftUI

/// A2: the name is picked from an endless wheel of keys (Figma 200:2732, 223:1499): Delete, Save,
/// then A to Z. Knob and Left / Right turn it, Confirm presses the key in the middle. On the phone
/// a swipe turns it and a tap presses a key.
struct AddMemberContent: View {
    let surface: Surface
    @Environment(AppState.self) private var state

    var body: some View {
        let w = surface.canvas.width

        ZStack(alignment: .topLeading) {
            ScreenHeading(surface: surface, title: title, subtitle: subtitle)

            NameField(surface: surface)
                .position(x: w / 2, y: surface.v(320, 414.5))

            LetterWheel(surface: surface)
                .frame(width: w, height: surface.v(140, 200))
                .position(x: w / 2, y: surface.v(573.8, 781.4))

            if surface == .phone {
                PhoneAppBar(back: .arrow) { state.handle(.cancel) }
            }
        }
        .frame(width: surface.canvas.width, height: surface.canvas.height)
    }

    private var title: Text {
        surface == .phone ? Text("Add a family member") : Text("Add a new member")
    }

    private var subtitle: Text {
        surface == .phone ? Text("Swipe to find a letter and tap to add it.\nTap Save when you're done!")
                          : Text("Pick letters with the knob,\nthen choose Save")
    }
}

/// The name being picked, with a blinking caret.
struct NameField: View {
    let surface: Surface
    @Environment(AppState.self) private var state
    @State private var caretOn = true

    var body: some View {
        let size = surface.s(CGSize(width: 307, height: 83.6), CGSize(width: 445, height: 121))
        HStack(spacing: surface.v(5, 7)) {
            Text(verbatim: state.nameDraft)
                .font(Theme.field(surface.v(44, 63.7)))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Capsule()
                .fill(Theme.caret)
                .frame(width: surface.v(3, 4.3), height: surface.v(37, 54))
                .opacity(caretOn ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, surface.v(20, 29))
        .frame(width: size.width, height: size.height)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: surface.v(20, 29)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: state.nameDraft))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.55))
                caretOn.toggle()
            }
        }
    }
}

/// The endless wheel of keys under the name. Lays itself out across its own width.
struct LetterWheel: View {
    let surface: Surface
    /// Taps on the phone; the onboarding passes its own so a key press goes through its step.
    var onTap: ((Int) -> Void)?
    @Environment(AppState.self) private var state
    @State private var dragStart: Int?

    var body: some View {
        GeometryReader { geo in
            let index = state.letterIndex
            let big = surface.v(104, 150.5), small = surface.v(80, 115.8), gap = surface.v(8, 11.6)
            let mid = geo.size.width / 2
            let y = geo.size.height / 2

            ZStack {
                ForEach((index - 5)...(index + 5), id: \.self) { i in
                    let k = i - index
                    let isCenter = k == 0
                    let x = isCenter ? mid
                        : mid + Double(k.signum()) * (big / 2 + gap + small / 2 + Double(abs(k) - 1) * (small + gap))
                    KeyFace(surface: surface, key: LetterKey.at(i), size: isCenter ? big : small,
                            selected: isCenter, squeeze: state.confirmCount)
                        .position(x: x, y: y)
                        .opacity(abs(k) >= 5 ? 0 : 1)
                        .onTapGesture {
                            guard surface == .phone else { return }
                            if let onTap { onTap(i) } else { state.tapLetterKey(at: i) }
                        }
                }
                if surface == .wall {
                    CursorView(size: 58, trigger: index)
                        .position(x: mid + big / 2 - 10, y: y + big / 2 - 4)
                }
            }
            .contentShape(Rectangle())
            .gesture(swipe(step: small + gap), including: surface == .phone ? .all : .subviews)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.letterIndex)
    }

    /// Phone: dragging sideways turns the wheel, one key per key width.
    private func swipe(step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let start = dragStart ?? state.letterIndex
                if dragStart == nil { dragStart = start }
                let target = start - Int((value.translation.width / step).rounded())
                if target != state.letterIndex { state.moveLetter(by: target - state.letterIndex) }
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// One key on the wheel: a letter, Delete (red) or Save (green check).
private struct KeyFace: View {
    let surface: Surface
    let key: LetterKey
    let size: CGFloat
    let selected: Bool
    let squeeze: Int

    var body: some View {
        let scale = size / surface.v(80, 115.8)
        Group {
            switch key {
            case .letter(let character):
                Text(String(character))
                    .font(Theme.key(surface.v(40, 57.9) * scale))
                    .foregroundStyle(Theme.ink)
            case .delete:
                Image(systemName: "trash")
                    .font(.system(size: surface.v(28, 40.5) * scale, weight: .medium))
                    .foregroundStyle(Theme.destructive)
                    .accessibilityLabel("Delete")
            case .save:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: surface.v(28, 40.5) * scale, weight: .medium))
                    .foregroundStyle(Theme.success)
                    .accessibilityLabel("Save")
            }
        }
        .frame(width: size, height: size)
        .background(Theme.key, in: RoundedRectangle(cornerRadius: size * 0.2))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.2)
                .strokeBorder(Theme.ink, lineWidth: surface == .wall && selected ? 6 : 0)
        }
        .confirmSqueeze(squeeze, active: selected)
    }
}
