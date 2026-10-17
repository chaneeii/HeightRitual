import SwiftUI

/// A full-width rounded button of the redesign. On the wall it names its controller button:
/// "Save (✓)", "Retake (↩)".
struct PillButton: View {
    enum Style { case primary, secondary, record }

    let surface: Surface
    let title: Text
    var systemImage: String?
    var control: ControlIcon.Glyph?
    var style: Style = .primary
    var size: CGSize
    var action: () -> Void = {}

    var body: some View {
        let fontSize = surface.v(17, 26)
        let label = HStack(spacing: surface.v(6, 8)) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            title
            if surface == .wall, let control {
                HStack(spacing: 2) {
                    Text(verbatim: "(")
                    ControlIcon(glyph: control, size: fontSize * 1.15)
                    Text(verbatim: ")")
                }
            }
        }
        .font(Theme.label(fontSize))
        .foregroundStyle(foreground)
        .frame(width: size.width, height: size.height)
        .background(background, in: Capsule())

        if surface == .phone {
            Button(action: action) { label }
                .buttonStyle(PressStyle())
        } else {
            label
        }
    }

    private var foreground: Color {
        switch style {
        case .primary, .record: return Theme.paper
        case .secondary: return surface == .wall ? Theme.paper : Theme.ink
        }
    }

    private var background: Color {
        switch style {
        case .primary: return Theme.ink
        case .record: return Theme.record
        case .secondary: return surface == .wall ? Theme.wallSecondaryButton : Theme.secondaryButton
        }
    }
}

/// Fills from empty to full over the five seconds of filming.
struct FilmProgressBar: View {
    var width: CGFloat
    var height: CGFloat
    var track: Color = Theme.progressTrack
    var fill: Color = Theme.progress
    @State private var fraction = 0.0

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(track)
            Capsule().fill(fill).frame(width: max(height, width * fraction))
        }
        .frame(width: width, height: height)
        .onAppear {
            fraction = 0
            withAnimation(.linear(duration: Double(AppState.filmSeconds))) { fraction = 1 }
        }
        .accessibilityHidden(true)
    }
}

/// The height dial (drawn after the reference picture in the redesign): a scale of centimetres
/// on an arc that turns under a fixed needle. The value is animatable, so the scale glides when
/// the knob steps it. On the phone it is dragged sideways.
struct HeightDial: View, Animatable {
    let surface: Surface
    var valueCM: Double
    let width: CGFloat
    let height: CGFloat

    var animatableData: Double {
        get { valueCM }
        set { valueCM = newValue }
    }

    /// Degrees of arc per centimetre.
    static let degreesPerCM = 14.0

    var radius: CGFloat { surface.v(176, 232) }

    var body: some View {
        Canvas { ctx, size in
            let k = surface.v(1, 1.32)
            let center = CGPoint(x: size.width / 2, y: surface.v(77, 102) + radius)
            func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
                let a = degrees * .pi / 180
                return CGPoint(x: center.x + r * CGFloat(Darwin.sin(a)), y: center.y - r * CGFloat(Darwin.cos(a)))
            }

            // The arc.
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(-180), endAngle: .degrees(0), clockwise: false)
            ctx.stroke(arc, with: .color(Theme.dialTick.opacity(0.18)), lineWidth: 1.5 * k)

            // Ticks every half centimetre, numbers on whole ones.
            let first = Int((valueCM - 7).rounded(.down) * 2), last = Int((valueCM + 7).rounded(.up) * 2)
            for half in first...last {
                let cm = Double(half) / 2
                let degrees = (cm - valueCM) * Self.degreesPerCM
                guard abs(degrees) < 82 else { continue }
                let whole = half % 2 == 0
                let fade = 1 - abs(degrees) / 95
                var tick = Path()
                tick.move(to: point(degrees, radius + 8 * k))
                tick.addLine(to: point(degrees, radius + (whole ? 30 : 19) * k))
                ctx.stroke(tick, with: .color(Theme.dialTick.opacity(fade)),
                           style: StrokeStyle(lineWidth: (whole ? 2.2 : 1.6) * k, lineCap: .round))
                if whole {
                    let near = abs(cm - valueCM) < 0.5
                    let label = Text(verbatim: "\(Int(cm))")
                        .font(.system(size: (near ? 24 : 17) * k, weight: near ? .bold : .regular).monospacedDigit())
                        .foregroundColor(near ? Theme.dialNeedle : Theme.dialTick.opacity(fade))
                    ctx.draw(label, at: point(degrees, radius + (near ? 58 : 46) * k), anchor: .center)
                }
            }

            // The needle with its dot, fixed in the middle.
            var needle = Path()
            needle.move(to: CGPoint(x: center.x, y: center.y - radius - 34 * k))
            needle.addLine(to: CGPoint(x: center.x, y: center.y - radius + 34 * k))
            ctx.stroke(needle, with: .color(Theme.dialNeedle), style: StrokeStyle(lineWidth: 5 * k, lineCap: .round))
            let dot = CGRect(x: center.x - 8 * k, y: center.y - radius - 8 * k, width: 16 * k, height: 16 * k)
            ctx.fill(Path(ellipseIn: dot), with: .color(Theme.dialNeedle))
        }
        .frame(width: width, height: height)
        .background(Theme.dialBackground)
        .accessibilityHidden(true)
    }
}

/// The record being made, as a black card: the clip if there is one, otherwise the outline at
/// the height on the dial, so turning the dial visibly grows or shrinks it.
struct DraftPreview: View {
    let size: CGSize
    @Environment(AppState.self) private var state

    var body: some View {
        let mm = state.draft?.heightMM ?? FootGuide.firstRecordMM
        ZStack {
            Color.black
            if let url = state.draft?.clip.rawVideoURL ?? state.draft?.clip.videoURL {
                LoopingVideo(url: url)
            } else {
                FootGuideOverlay(guide: FootGuide.make(camera: state.settings.camera, outlineMM: mm),
                                 accent: Theme.guide)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mm)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: size.width * 0.06, style: .continuous))
    }
}
