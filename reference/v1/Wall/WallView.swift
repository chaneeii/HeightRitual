import SwiftUI

/// The projected wall image. On the projector it fills the screen; on the phone it is a small preview.
struct WallView: View {
    @Environment(AppState.self) private var state
    var isExternal: Bool

    var body: some View {
        GeometryReader { geo in
            let logical = state.calibration.logicalSize(for: geo.size)
            WallCanvas(model: state.wallModel)
                .frame(width: logical.width, height: logical.height)
                .rotationEffect(.degrees(Double(state.calibration.rotation)))
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear { if isExternal { state.wallSize = geo.size } }
                .onChange(of: geo.size) { _, size in if isExternal { state.wallSize = size } }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

/// Converts real centimetres on the wall into points on the projected image.
struct WallGeometry {
    let size: CGSize
    let calibration: Calibration

    var centerX: CGFloat { size.width / 2 + CGFloat(calibration.shiftPt) }
    func y(_ cm: Double) -> CGFloat { size.height - CGFloat(calibration.floorPt) - CGFloat(cm * calibration.ptPerCM) }
    func length(_ cm: Double) -> CGFloat { CGFloat(cm * calibration.ptPerCM) }
    var topCM: Double { max(0, (Double(size.height) - calibration.floorPt) / calibration.ptPerCM) }
}

struct WallCanvas: View {
    let model: WallModel

    private let pencil = Color(red: 0.93, green: 0.87, blue: 0.76)
    private let live = Color(red: 0.91, green: 0.45, blue: 0.33)

    var body: some View {
        Canvas { ctx, size in
            let g = WallGeometry(size: size, calibration: model.calibration)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

            if model.screen == .calibrate {
                drawRuler(ctx, g)
                return
            }

            let figureX = g.centerX - g.length(8)
            let lineLeft = g.centerX - g.length(30)
            let lineRight = g.centerX + g.length(22)
            let labelX = lineRight + g.length(2)
            let fontSize = max(14, g.length(2.2))

            // 1. Life-size figure, feet on the floor line.
            if let heightCM = model.figureHeightCM {
                if let photo = model.figurePhoto, photo.size.height > 0 {
                    let h = g.length(heightCM)
                    let w = h * photo.size.width / photo.size.height
                    let rect = CGRect(x: figureX - w / 2, y: g.y(heightCM), width: w, height: h)
                    ctx.draw(Image(uiImage: photo), in: rect)
                } else {
                    drawOutline(ctx, g, heightCM: heightCM, centerX: figureX)
                }
            }

            // 2. Pencil marks for every record, the selected one stronger.
            for mark in model.marks {
                let y = g.y(mark.heightCM)
                var line = Path()
                line.move(to: CGPoint(x: lineLeft, y: y))
                line.addLine(to: CGPoint(x: lineRight, y: y))
                ctx.stroke(line,
                           with: .color(mark.selected ? model.accent : pencil.opacity(0.45)),
                           lineWidth: mark.selected ? 3 : 1.5)
                let text = Text(mark.label)
                    .font(.system(size: mark.selected ? fontSize * 1.25 : fontSize, design: .serif))
                    .italic()
                    .foregroundColor(mark.selected ? model.accent : pencil.opacity(0.6))
                ctx.draw(text, at: CGPoint(x: labelX, y: y), anchor: .leading)
            }

            if let caption = model.caption, let heightCM = model.figureHeightCM {
                let text = Text(caption)
                    .font(.system(size: fontSize, design: .serif)).italic()
                    .foregroundColor(pencil.opacity(0.85))
                ctx.draw(text, at: CGPoint(x: labelX, y: g.y(heightCM) + fontSize * 1.6), anchor: .leading)
            }

            // 3. Today's height while recording.
            if let heightCM = model.liveHeightCM {
                let y = g.y(heightCM)
                var line = Path()
                line.move(to: CGPoint(x: lineLeft, y: y))
                line.addLine(to: CGPoint(x: lineRight, y: y))
                ctx.stroke(line, with: .color(live), style: StrokeStyle(lineWidth: 2.5, dash: [10, 7]))
                let text = Text("Now  \(heightCM.cmText)")
                    .font(.system(size: fontSize * 1.25, design: .serif)).italic()
                    .foregroundColor(live)
                ctx.draw(text, at: CGPoint(x: labelX, y: y), anchor: .leading)
                if let caption = model.liveCaption {
                    let sub = Text(caption)
                        .font(.system(size: fontSize, design: .serif)).italic()
                        .foregroundColor(live.opacity(0.8))
                    ctx.draw(sub, at: CGPoint(x: labelX, y: y + fontSize * 1.6), anchor: .leading)
                }
            }

            if let n = model.countdown {
                let text = Text("\(n)")
                    .font(.system(size: g.length(18), weight: .light, design: .serif))
                    .foregroundColor(pencil.opacity(0.8))
                ctx.draw(text, at: CGPoint(x: lineRight + g.length(14), y: g.y(30)), anchor: .center)
            }

            if let headline = model.headline {
                let text = Text(headline)
                    .font(.system(size: g.length(7), design: .serif)).italic()
                    .foregroundColor(model.accent)
                ctx.draw(text, at: CGPoint(x: g.centerX, y: g.y(min(g.topCM - 15, 150))), anchor: .center)
            }
        }
    }

    /// Soft outline of a child, used for sample records that have no photo.
    private func drawOutline(_ ctx: GraphicsContext, _ g: WallGeometry, heightCM: Double, centerX: CGFloat) {
        let unit = g.length(heightCM) / 125
        let floor = g.y(0)
        func r(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: centerX + x0 * unit, y: floor - y1 * unit, width: (x1 - x0) * unit, height: (y1 - y0) * unit)
        }
        var shape = Path()
        shape.addEllipse(in: r(-10, 105, 10, 125))                               // head
        shape.addRoundedRect(in: r(-12, 55, 12, 100), cornerSize: CGSize(width: 6 * unit, height: 6 * unit))
        shape.addRoundedRect(in: r(-18, 58, -13, 96), cornerSize: CGSize(width: 2.5 * unit, height: 2.5 * unit))
        shape.addRoundedRect(in: r(13, 58, 18, 96), cornerSize: CGSize(width: 2.5 * unit, height: 2.5 * unit))
        shape.addRoundedRect(in: r(-10, 0, -1, 57), cornerSize: CGSize(width: 2 * unit, height: 2 * unit))
        shape.addRoundedRect(in: r(1, 0, 10, 57), cornerSize: CGSize(width: 2 * unit, height: 2 * unit))
        ctx.fill(shape, with: .color(model.accent.opacity(0.18)))
        ctx.stroke(shape, with: .color(model.accent.opacity(0.5)), lineWidth: 1.5)
    }

    /// Centimetre ruler from the floor up, used while calibrating with a real tape measure.
    private func drawRuler(_ ctx: GraphicsContext, _ g: WallGeometry) {
        let left = g.centerX - g.length(30)
        let right = g.centerX + g.length(30)
        let top = min(Int(g.topCM), 200)
        for cm in stride(from: 0, through: top, by: 5) {
            let y = g.y(Double(cm))
            let key = cm == 0 || cm == 100 || cm == 150
            let major = cm % 10 == 0
            var line = Path()
            line.move(to: CGPoint(x: major ? left : right - g.length(8), y: y))
            line.addLine(to: CGPoint(x: right, y: y))
            ctx.stroke(line,
                       with: .color(key ? Color.yellow : Color.white.opacity(major ? 0.7 : 0.4)),
                       lineWidth: key ? 3 : (major ? 1.5 : 1))
            if major {
                let label = Text(key ? "\(cm) cm" : "\(cm)")
                    .font(.system(size: key ? 20 : 15, weight: key ? .semibold : .regular, design: .monospaced))
                    .foregroundColor(key ? .yellow : .white)
                ctx.draw(label, at: CGPoint(x: right + 8, y: y), anchor: .leading)
            }
        }
        if g.topCM >= 170 {
            let y = g.y(170)
            var line = Path()
            line.move(to: CGPoint(x: left, y: y))
            line.addLine(to: CGPoint(x: right, y: y))
            ctx.stroke(line, with: .color(.green), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        }
        var center = Path()
        center.move(to: CGPoint(x: g.centerX, y: g.y(0)))
        center.addLine(to: CGPoint(x: g.centerX, y: g.y(Double(top))))
        ctx.stroke(center, with: .color(.white.opacity(0.3)), lineWidth: 1)

        let status = Text("Visible up to \(Int(g.topCM)) cm   ·   adjusting: \(model.calibrationParam.title)")
            .font(.system(size: 15, design: .monospaced))
            .foregroundColor(g.topCM >= 170 ? .green : .orange)
        ctx.draw(status, at: CGPoint(x: 16, y: 24), anchor: .leading)
        ctx.stroke(Path(CGRect(origin: .zero, size: g.size).insetBy(dx: 1, dy: 1)),
                   with: .color(.white.opacity(0.5)), lineWidth: 2)
    }
}
