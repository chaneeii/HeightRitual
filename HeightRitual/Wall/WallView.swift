import AVFoundation
import SwiftUI

/// The wall image, drawn in the 9:16 strip (`Calibration.stripSize`). On the projector the strip
/// sits in a black picture that is rotated for a projector on its side; on the phone only the
/// strip is shown, upright and scaled to fit.
struct WallView: View {
    var isExternal = false
    @Environment(AppState.self) private var state

    var body: some View {
        GeometryReader { geo in
            let calibration = state.settings.wall
            let picture = calibration.logicalSize(for: state.wallSize)
            let strip = calibration.stripSize(for: state.wallSize)
            let outer = isExternal ? picture : strip
            let scale = isExternal ? 1 : min(geo.size.width / strip.width, geo.size.height / strip.height)
            let model = state.wallModel
            WallCanvas(model: model)
                .overlay { WallClipOverlay(model: model, player: state.wallPlayer.player) }
                .overlay {
                    // Layers (SPEC 10): wall, marks, clip. A clip with its background would hide
                    // the marks, so they are drawn once more above it.
                    if model.figure?.hasClip == true, model.figure?.opaque == true {
                        WallCanvas(model: model, marksOnly: true).allowsHitTesting(false)
                    }
                }
                .frame(width: strip.width, height: strip.height)
                .clipped()
                .frame(width: outer.width, height: outer.height)
                .background(Color.black)
                .rotationEffect(.degrees(isExternal ? Double(calibration.rotation) : 0))
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear { if isExternal { state.wallSize = geo.size } }
                .onChange(of: geo.size) { _, size in if isExternal { state.wallSize = size } }
        }
        .background(Color.black)
        .modifier(IgnoreSafeAreaIfExternal(isExternal: isExternal))
    }
}

private struct IgnoreSafeAreaIfExternal: ViewModifier {
    let isExternal: Bool
    func body(content: Content) -> some View {
        if isExternal { content.ignoresSafeArea() } else { content }
    }
}

/// Converts real centimetres on the wall into points on the projected image.
struct WallGeometry {
    let size: CGSize
    let calibration: Calibration

    var centerX: CGFloat { size.width / 2 }
    func y(cm: Double) -> CGFloat { CGFloat(calibration.y(cm: cm, imageHeight: Double(size.height))) }
    func y(mm: Int) -> CGFloat { y(cm: Double(mm) / 10) }
    func length(cm: Double) -> CGFloat { CGFloat(cm * calibration.ptPerCM) }
    var topCM: Double { calibration.visibleTopCM(imageHeight: Double(size.height)) }
}

struct WallCanvas: View {
    let model: WallModel
    /// Only marks and captions on a clear background, for the layer above an opaque clip.
    var marksOnly = false

    /// Warm off-white, like pencil on a wall (SPEC 10).
    static let pencil = Color(red: 0.93, green: 0.87, blue: 0.76)
    /// The line of a record being made.
    static let coral = Color(red: 0.96, green: 0.50, blue: 0.42)

    var body: some View {
        Canvas { ctx, size in
            let g = WallGeometry(size: size, calibration: model.calibration)
            if marksOnly {
                drawMarks(ctx, g)
                return
            }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            switch model.kind {
            case .idle: drawRuler(ctx, g, faint: true)
            case .ruler: drawRuler(ctx, g, faint: false)
            case .marks: drawMarks(ctx, g)
            case .footGuide: drawFootGuide(ctx, g)
            case .dark: drawNumber(ctx, g)
            case .cameraLines: drawCameraLines(ctx, g)
            }
        }
    }

    private var pencil: Color { Self.pencil }

    private func font(_ g: WallGeometry, _ factor: Double = 1) -> CGFloat {
        max(14, g.length(cm: 2.2)) * factor
    }

    // MARK: Marks, figure, captions

    private func drawMarks(_ ctx: GraphicsContext, _ g: WallGeometry) {
        let figureX = g.centerX - g.length(cm: 8)
        let lineLeft = g.centerX - g.length(cm: 30)
        let lineRight = g.centerX + g.length(cm: 22)
        let labelX = lineRight + g.length(cm: 2)
        let size = font(g)

        // 1. Life-size figure, feet on the floor line. Cut off at the top when taller than the picture.
        if !marksOnly, let figure = model.figure, !figure.hasClip {
            drawOutline(ctx, g, heightCM: Double(figure.heightMM) / 10, centerX: figureX)
        }

        // 2. A pencil mark for every record; the selected one in the member's colour.
        for mark in model.marks {
            let y = g.y(mm: mark.heightMM)
            ctx.stroke(line(lineLeft, lineRight, y),
                       with: .color(mark.selected ? model.accent : pencil.opacity(0.45)),
                       lineWidth: mark.selected ? 3 : 1.5)
            let text = Text(mark.label)
                .font(.system(size: mark.selected ? size * 1.25 : size, design: .serif))
                .italic()
                .foregroundColor(mark.selected ? model.accent : pencil.opacity(0.6))
            ctx.draw(text, at: CGPoint(x: labelX, y: y), anchor: .leading)
        }

        // Caption just above the selected mark's left end, inside the narrow strip; kept inside
        // the picture for members taller than its top.
        if let caption = model.caption, let figure = model.figure {
            let y = max(g.y(mm: figure.heightMM) - size * 0.9, size * 1.5)
            let text = Text(caption)
                .font(.system(size: size * 1.1, design: .serif)).italic()
                .foregroundColor(model.accent)
            ctx.draw(text, at: CGPoint(x: lineLeft, y: y), anchor: .leading)
        }

        // 3. The record being made follows the number on the phone.
        if let mm = model.liveMM {
            let y = g.y(mm: mm)
            ctx.stroke(line(lineLeft, lineRight, y), with: .color(Self.coral),
                       style: StrokeStyle(lineWidth: 2.5, dash: [10, 7]))
            if let label = model.liveLabel {
                let text = Text(label)
                    .font(.system(size: size * 1.25, design: .serif)).italic()
                    .foregroundColor(Self.coral)
                ctx.draw(text, at: CGPoint(x: labelX, y: y), anchor: .leading)
            }
        }

        if let headline = model.headline {
            let text = Text(headline)
                .font(.system(size: g.length(cm: 7), design: .serif)).italic()
                .foregroundColor(model.marks.isEmpty && model.figure == nil ? pencil.opacity(0.8) : model.accent)
            let cm = min(g.topCM - 15, 150)
            ctx.draw(text, at: CGPoint(x: g.centerX, y: g.y(cm: cm)), anchor: .center)
        }
    }

    // MARK: Foot guide (M2 ready)

    private func drawFootGuide(_ ctx: GraphicsContext, _ g: WallGeometry) {
        let floor = g.y(cm: 0)
        ctx.stroke(line(g.centerX - g.length(cm: 40), g.centerX + g.length(cm: 40), floor),
                   with: .color(pencil.opacity(0.7)), lineWidth: 2)
        // Two foot marks, heels on the floor line.
        for side in [-1.0, 1.0] {
            let rect = CGRect(x: g.centerX + g.length(cm: side < 0 ? -12 : 2), y: floor - g.length(cm: 3),
                              width: g.length(cm: 10), height: g.length(cm: 3))
            ctx.fill(Path(roundedRect: rect, cornerRadius: g.length(cm: 1.5)), with: .color(model.accent.opacity(0.6)))
        }
        if let mm = model.guideMM {
            drawOutline(ctx, g, heightCM: Double(mm) / 10, centerX: g.centerX)
        }
        let text = Text("Heels on the line, back against the wall")
            .font(.system(size: font(g), design: .serif)).italic()
            .foregroundColor(pencil.opacity(0.8))
        ctx.draw(text, at: CGPoint(x: g.centerX, y: floor + font(g) * 1.2), anchor: .center)
    }

    // MARK: Countdown and filming

    private func drawNumber(_ ctx: GraphicsContext, _ g: WallGeometry) {
        guard let n = model.bigNumber else { return }
        let text = Text("\(n)")
            .font(.system(size: g.length(cm: 18), weight: .light, design: .serif))
            .foregroundColor(pencil.opacity(0.6))
        ctx.draw(text, at: CGPoint(x: g.centerX + g.length(cm: 45), y: g.y(cm: 30)), anchor: .center)
    }

    // MARK: Setup pages

    /// S3: bright lines at 0 and 100 cm; the phone's camera lines are dragged onto them.
    private func drawCameraLines(_ ctx: GraphicsContext, _ g: WallGeometry) {
        for cm in [0.0, 100.0] {
            let y = g.y(cm: cm)
            ctx.stroke(line(0, g.size.width, y), with: .color(.white), lineWidth: 6)
            let text = Text(cm == 0 ? LocalizedStringKey("Floor") : "100 cm")
                .font(.system(size: font(g, 1.2), design: .serif)).italic()
                .foregroundColor(.white)
            ctx.draw(text, at: CGPoint(x: 16, y: y - font(g)), anchor: .leading)
        }
    }

    // MARK: Shapes

    private func line(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x0, y: y))
        path.addLine(to: CGPoint(x: x1, y: y))
        return path
    }

    /// Soft outline of a person, used for records without a clip.
    private func drawOutline(_ ctx: GraphicsContext, _ g: WallGeometry, heightCM: Double, centerX: CGFloat) {
        let shape = PersonOutline.path(heightPt: g.length(cm: heightCM), centerX: centerX, floorY: g.y(cm: 0))
        ctx.fill(shape, with: .color(model.accent.opacity(0.18)))
        ctx.stroke(shape, with: .color(model.accent.opacity(0.5)), lineWidth: 1.5)
    }

    /// Centimetre ruler from the floor up. Faint on Home; bright on fit to wall, with 0, 100 and
    /// 150 highlighted and a dashed line at 170 (SPEC 5, S2).
    private func drawRuler(_ ctx: GraphicsContext, _ g: WallGeometry, faint: Bool) {
        let left = g.centerX - g.length(cm: 30)
        let right = g.centerX + g.length(cm: 30)
        let top = min(Int(g.topCM), 220)
        let base = pencil.opacity(faint ? 0.18 : 0.7)
        for cm in stride(from: 0, through: top, by: 5) {
            let y = g.y(cm: Double(cm))
            let key = !faint && (cm == 0 || cm == 100 || cm == 150)
            let major = cm % 10 == 0
            ctx.stroke(line(major ? left : right - g.length(cm: 8), right, y),
                       with: .color(key ? .white : base), lineWidth: key ? 3 : (major ? 1.5 : 1))
            if major && (!faint || cm % 50 == 0) {
                let label = Text(verbatim: cm % 50 == 0 && !faint ? "\(cm) cm" : "\(cm)")
                    .font(.system(size: key ? font(g, 1.1) : font(g, 0.8), design: .serif))
                    .italic()
                    .foregroundColor(key ? .white : base)
                ctx.draw(label, at: CGPoint(x: right + 8, y: y), anchor: .leading)
            }
        }
        guard !faint else { return }
        if g.topCM >= 170 {
            ctx.stroke(line(left, right, g.y(cm: 170)), with: .color(.white.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        }
        let label = model.fitValue.map { L("Adjusting: \($0.title)") } ?? ""
        let status = Text("Top of picture: \(Int(g.topCM)) cm   \(label)")
            .font(.system(size: font(g, 0.8), design: .serif)).italic()
            .foregroundColor(pencil)
        ctx.draw(status, at: CGPoint(x: 16, y: 24), anchor: .leading)
        ctx.stroke(Path(CGRect(origin: .zero, size: g.size).insetBy(dx: 1, dy: 1)),
                   with: .color(.white.opacity(0.5)), lineWidth: 2)
    }
}

/// The selected record's clip, life-size: the standing feet on the floor line, the body as tall as
/// the record's height (SPEC 9: drawn height = heightCM * ptPerCM / bodyRatio).
private struct WallClipOverlay: View {
    let model: WallModel
    let player: AVPlayer

    var body: some View {
        GeometryReader { geo in
            if let figure = model.figure, figure.hasClip {
                let g = WallGeometry(size: geo.size, calibration: model.calibration)
                let bodyPt = g.length(cm: Double(figure.heightMM) / 10)
                // Without layout numbers (clip kept without a person) the frame is the body.
                let clipHeight = bodyPt / CGFloat(figure.bodyRatio ?? 0.85)
                let clipWidth = clipHeight * CGFloat(figure.aspect ?? 9.0 / 16.0)
                let bottom = g.y(cm: 0) + CGFloat(figure.floorRatio ?? 0.05) * clipHeight
                PlayerLayerView(player: player)
                    .frame(width: clipWidth, height: clipHeight)
                    .position(x: g.centerX - g.length(cm: 8), y: bottom - clipHeight / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// An AVPlayerLayer on a clear background, so the cut-out's transparent parts show the wall.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
