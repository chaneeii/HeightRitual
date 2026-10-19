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
                .overlay { if model.kind == .screen { WallScreen() } }
                .overlay { WallClipOverlay(model: model, player: state.wallPlayer.player) }
                .overlay { WallScreenOverlay(route: state.route) }
                .overlay {
                    switch model.kind {
                    case .settingsMenu: WallSettingsMenu()
                    case .settingsUnits: WallUnitsPage()
                    case .settingsPermissions: WallPermissionsPage()
                    case .settingsGuide: WallSetupGuidePage()
                    default: EmptyView()
                    }
                }
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
            case .screen: ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.paper))
            case .settingsMenu, .settingsUnits, .settingsPermissions, .settingsGuide:
                break    // views above the canvas: WallSettingsMenu and the settings pages below it
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
            drawOutline(ctx, g, heightCM: Double(figure.heightMM) / 10, centerX: figureX, filled: true)
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
        if model.showsText, let caption = model.caption, let figure = model.figure {
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

        if model.showsText, let headline = model.headline {
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
    /// `filled`: a record without a clip (the sample family), drawn as a white figure at 80 % so it
    /// shows; the outline to stand in while filming stays see-through.
    private func drawOutline(_ ctx: GraphicsContext, _ g: WallGeometry, heightCM: Double, centerX: CGFloat,
                             filled: Bool = false) {
        let shape = PersonOutline.path(heightPt: g.length(cm: heightCM), centerX: centerX, floorY: g.y(cm: 0))
        ctx.fill(shape, with: .color(filled ? Color.white.opacity(0.8) : model.accent.opacity(0.18)))
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
        let status = Text("Top of picture: \(Int(g.topCM)) cm")
            .font(.system(size: font(g, 0.8), design: .serif)).italic()
            .foregroundColor(pencil)
        ctx.draw(status, at: CGPoint(x: 16, y: 24), anchor: .leading)
        // Floor line | Size: Left and Right choose (filled orange), the knob moves the chosen one.
        if let chosen = model.fitValue {
            let size = font(g, 2.0)
            var x: CGFloat = 16
            for value in FitValue.allCases {
                let selected = value == chosen
                let text = ctx.resolve(Text(verbatim: value.title)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(selected ? .white : pencil))
                let measured = text.measure(in: CGSize(width: g.size.width, height: size * 3))
                let pill = CGRect(x: x, y: 24 + size, width: measured.width + size * 1.4,
                                  height: measured.height + size * 0.8)
                let shape = Path(roundedRect: pill, cornerRadius: pill.height / 2)
                if selected {
                    ctx.fill(shape, with: .color(WallBackIcon.orange))
                } else {
                    ctx.stroke(shape, with: .color(pencil.opacity(0.6)), lineWidth: 2)
                }
                ctx.draw(text, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
                x = pill.maxX + size * 0.6
            }
        }
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
    /// Fill the frame and crop, instead of fitting the whole clip.
    var fill = false

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// The wall's own screen text laid over the life-size picture: while filming and in Lookback.
private struct WallScreenOverlay: View {
    let route: Route

    var body: some View {
        switch route {
        case .makeFilm(let film): WallFilmOverlay(film: film)
        case .memoryWall, .record: WallPlaybackOverlay()
        default: EmptyView()
        }
    }
}

/// The settings list on the wall while Settings is open on the phone: the same items and values
/// as rounded tiles in two columns, with Setup guide as a pill beside the title. Sized from the picture's width, so it
/// fills the projector and still reads in the phone's small wall copy.
private struct WallSettingsMenu: View {
    @Environment(AppState.self) private var state

    private struct Tile: Identifiable {
        let id: SettingsTile
        let title: LocalizedStringKey
        var detail: LocalizedStringKey?
        let systemImage: String
        var value: String?
        var destructive = false
    }

    private static let text = Color(red: 0.08, green: 0.10, blue: 0.08)

    private var rows: [[Tile]] {
        let settings = state.settings
        let tiles = [
            Tile(id: .family, title: "Family", detail: "Add, rename or remove the people you measure",
                 systemImage: "person.2", value: "\(state.store.members.count)"),
            Tile(id: .fitToWall, title: "Fit to wall", detail: "Make projected centimetres match a tape measure",
                 systemImage: "ruler"),
            Tile(id: .cameraPosition, title: "Camera position", detail: "Where the floor and 100 cm are in the camera picture",
                 systemImage: "camera.viewfinder", value: settings.camera == nil ? L("Not set") : L("Set")),
            Tile(id: .units, title: "Units", detail: "For every height on the phone and the wall",
                 systemImage: "textformat.123",
                 value: settings.unit == .cm ? L("Centimetres") : L("Feet and inches")),
            Tile(id: .pointColour, title: "Point colour", detail: "Borders, buttons and the dial, on the phone and the wall",
                 systemImage: "paintpalette",
                 value: settings.accentIndex.map { "Colour \($0 + 1)" } ?? "Black"),
            Tile(id: .sound, title: "Sound", detail: "Record and play sound with each clip",
                 systemImage: "speaker.wave.2", value: settings.soundOn ? L("On") : L("Off")),
            Tile(id: .controller, title: "Controller", detail: "Connection, and a test of every button",
                 systemImage: "gamecontroller",
                 value: state.controllerStatus == .connected ? L("Connected") : state.controllerStatus.label),
            Tile(id: .permissions, title: "Permissions", detail: "Camera, Bluetooth and microphone",
                 systemImage: "hand.raised"),
            Tile(id: .sampleFamily, title: "Load sample family", detail: "Nora and Leo, to try Memory without filming",
                 systemImage: "person.3"),
            Tile(id: .deleteEverything, title: "Delete everything", systemImage: "trash", destructive: true),
        ]
        // Two per row; an odd last tile stands alone on the left.
        return stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
    }

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / 100
            let rowCount = CGFloat(rows.count)
            // Padding, the title and the gaps, then six rows of the same height.
            let tileHeight = (geo.size.height - unit * 8 - unit * 7.5 - unit * 2.5 - unit * 2.5 * (rowCount - 1)) / rowCount
            VStack(alignment: .leading, spacing: unit * 2.5) {
                HStack(alignment: .center, spacing: unit * 3) {
                    WallBackIcon(unit: unit)
                    Text("Settings")
                        .font(.system(size: unit * 6, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer(minLength: unit * 2)
                    setupGuide(unit: unit)
                }
                Grid(horizontalSpacing: unit * 2.5, verticalSpacing: unit * 2.5) {
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(rows[row]) { tile in
                                tileView(tile, unit: unit)
                                    .frame(height: max(0, tileHeight))
                            }
                        }
                    }
                }
            }
            .padding(unit * 4)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Color.black)
    }

    /// Setup guide sits apart from the tiles, as a pill beside the title.
    private func setupGuide(unit: CGFloat) -> some View {
        Label {
            Text("Setup guide")
                .font(.system(size: unit * 3.4, weight: .semibold))
        } icon: {
            Image(systemName: "book")
                .font(.system(size: unit * 3.4))
        }
        .foregroundStyle(Self.text)
        .padding(.horizontal, unit * 3)
        .padding(.vertical, unit * 1.6)
        .background(SettingsStyle.row, in: Capsule())
        .overlay {
            if state.settingsHighlight == .setupGuide {
                Capsule().strokeBorder(WallBackIcon.orange, lineWidth: unit * 1.2)
            }
        }
    }

    private func tileView(_ tile: Tile, unit: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: unit * 0.8) {
            HStack(alignment: .top) {
                Image(systemName: tile.systemImage)
                    .font(.system(size: unit * 4.5))
                    .foregroundStyle(tile.destructive ? Color.red : SettingsStyle.icon)
                Spacer(minLength: unit)
                if let value = tile.value {
                    Text(verbatim: value)
                        .font(.system(size: unit * 3, weight: .semibold))
                        .foregroundStyle(Self.text.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            Spacer(minLength: 0)
            Text(tile.title)
                .font(.system(size: unit * 3.8, weight: .semibold))
                .foregroundStyle(tile.destructive ? Color.red : Self.text)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = tile.detail {
                Text(detail)
                    .font(.system(size: unit * 2.6))
                    .foregroundStyle(Self.text.opacity(0.65))
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(unit * 2.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsStyle.row, in: RoundedRectangle(cornerRadius: unit * 4, style: .continuous))
        .overlay {
            if state.settingsHighlight == tile.id {
                RoundedRectangle(cornerRadius: unit * 4, style: .continuous)
                    .strokeBorder(WallBackIcon.orange, lineWidth: unit * 1.2)
            }
        }
    }
}

/// The back icon on the projector's settings pages: the controller's Back button goes back.
/// Only shown; the projector cannot be touched.
private struct WallBackIcon: View {
    let unit: CGFloat
    /// The orange of the back icon, also used to outline the controller's choice.
    static let orange = Color(red: 0.93, green: 0.42, blue: 0.18)

    var body: some View {
        Image(systemName: "arrowshape.turn.up.left.fill")
            .font(.system(size: unit * 4.6, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: unit * 9.5, height: unit * 9.5)
            .background(Self.orange, in: RoundedRectangle(cornerRadius: unit * 2.6, style: .continuous))
    }
}

/// One option on a projector settings page.
private struct WallChoice: Identifiable {
    let id: Int
    let title: Text
    var detail: String?
}

/// A projector settings page with options: back icon and title, the options as rows, the saved one
/// ticked and the controller's choice outlined in orange.
private struct WallChoicePage: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let choices: [WallChoice]
    let saved: Int
    let highlighted: Int
    private static let text = Color(red: 0.08, green: 0.10, blue: 0.08)

    var body: some View {
        WallSettingsPage(title: title, subtitle: subtitle) { unit in
            ForEach(choices) { choice in
                row(choice, unit: unit)
            }
        }
    }

    private func row(_ choice: WallChoice, unit: CGFloat) -> some View {
        HStack(spacing: unit * 3) {
            VStack(alignment: .leading, spacing: unit * 1) {
                choice.title
                    .font(.system(size: unit * 5, weight: .semibold))
                if let detail = choice.detail {
                    Text(verbatim: detail)
                        .font(.system(size: unit * 3.6))
                        .opacity(0.7)
                }
            }
            Spacer(minLength: 0)
            if choice.id == saved {
                Image(systemName: "checkmark")
                    .font(.system(size: unit * 5, weight: .bold))
            }
        }
        .foregroundStyle(Self.text)
        .padding(unit * 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsStyle.row, in: RoundedRectangle(cornerRadius: unit * 4, style: .continuous))
        .overlay {
            if choice.id == highlighted {
                RoundedRectangle(cornerRadius: unit * 4, style: .continuous)
                    .strokeBorder(WallBackIcon.orange, lineWidth: unit * 1.2)
            }
        }
    }
}

/// The frame of every projector settings page: back icon, title and subtitle, then the content.
private struct WallSettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / 100
            VStack(alignment: .leading, spacing: unit * 4) {
                HStack(alignment: .center, spacing: unit * 3) {
                    WallBackIcon(unit: unit)
                    Text(title)
                        .font(.system(size: unit * 6, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(subtitle)
                    .font(.system(size: unit * 3.4))
                    .foregroundStyle(.white.opacity(0.75))
                content(unit)
                Spacer(minLength: 0)
            }
            .padding(unit * 4)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Color.black)
    }
}

/// S4 Units on the projector. The knob, Left and Right choose; Select saves and goes back to the
/// grid; Back goes back.
private struct WallUnitsPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let units = HeightUnit.allCases
        WallChoicePage(
            title: "Units", subtitle: "For every height on the phone and the wall",
            choices: units.enumerated().map { index, unit in
                WallChoice(id: index, title: Text(unit == .cm ? "Centimetres" : "Feet and inches"),
                           detail: HeightFormatter.text(1210, unit: unit))
            },
            saved: units.firstIndex(of: state.settings.unit) ?? 0,
            highlighted: units.firstIndex(of: state.unitHighlight) ?? 0)
    }
}

/// S5 Permissions on the projector: each permission and whether it is allowed. Nothing to choose;
/// permissions are changed on the phone, where iOS asks. Back goes back to the grid.
private struct WallPermissionsPage: View {
    @Environment(AppState.self) private var state
    private static let text = Color(red: 0.08, green: 0.10, blue: 0.08)

    var body: some View {
        // iOS does not report changes, so look again every second.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            WallSettingsPage(title: "Permissions", subtitle: "Camera, Bluetooth and microphone") { unit in
                row("Camera", why: "Films the clip.", access: .camera, unit: unit)
                row("Bluetooth", why: "Connects the controller.", access: .bluetooth, unit: unit)
                if state.settings.soundOn {
                    row("Microphone", why: "Records sound with the clip.", access: .microphone, unit: unit)
                }
                Text("Change permissions on the phone.")
                    .font(.system(size: unit * 3.4))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func row(_ title: LocalizedStringKey, why: LocalizedStringKey, access: PermissionAccess,
                     unit: CGFloat) -> some View {
        HStack(spacing: unit * 3) {
            VStack(alignment: .leading, spacing: unit * 1) {
                Text(title)
                    .font(.system(size: unit * 5, weight: .semibold))
                Text(why)
                    .font(.system(size: unit * 3.6))
                    .opacity(0.7)
            }
            Spacer(minLength: 0)
            Label {
                switch access {
                case .allowed: Text("Allowed")
                case .notAsked: Text("Not asked yet")
                case .refused: Text("Not allowed")
                }
            } icon: {
                switch access {
                case .allowed: Image(systemName: "checkmark.circle.fill")
                case .notAsked: Image(systemName: "questionmark.circle")
                case .refused: Image(systemName: "xmark.circle.fill")
                }
            }
            .font(.system(size: unit * 3.8, weight: .semibold))
            .foregroundStyle(access == .refused ? Color.red : Self.text)
        }
        .foregroundStyle(Self.text)
        .padding(unit * 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsStyle.row, in: RoundedRectangle(cornerRadius: unit * 4, style: .continuous))
    }
}

/// Setup guide on the projector: the same two pictures as the phone's Setup guide page. Only
/// shown; Back goes back to the grid.
private struct WallSetupGuidePage: View {
    var body: some View {
        WallSettingsPage(title: "Setup guide", subtitle: "Where to put the projector and the phone") { unit in
            ForEach(["SetupGuideProjector", "SetupGuideCamera"], id: \.self) { name in
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: unit * 3, style: .continuous))
            }
        }
    }
}
