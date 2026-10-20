import SwiftUI

/// Story-style segments, one per record: the ones up to the selected record are filled.
struct StoryIndicator: View {
    let count: Int
    let index: Int
    var width: CGFloat
    var height: CGFloat = 3
    var gap: CGFloat = 5

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Capsule()
                    .fill(i <= index ? Color.white : Color.white.opacity(0.35))
            }
        }
        .frame(width: width, height: height)
        .animation(.easeOut(duration: 0.25), value: index)
        .accessibilityHidden(true)
    }
}

/// The selected record as the clip card shows it: the clip when there is one, otherwise the
/// outline at the record's height, scaled against the tallest record so growth shows.
struct RecordFigure: View {
    let record: GrowthRecord?
    let tallestMM: Int
    /// How much of the card's height the tallest record's outline takes.
    var share: CGFloat = 0.78
    @Environment(AppState.self) private var state

    var body: some View {
        GeometryReader { geo in
            let floor = geo.size.height * 0.89
            ZStack(alignment: .topLeading) {
                Color.black
                if let record, state.clipURL(record) != nil {
                    PlayerLayerView(player: state.wallPlayer.player)
                } else if let record {
                    let full = floor * share
                    let h = full * CGFloat(record.heightMM) / CGFloat(max(tallestMM, 1))
                    let outline = PersonOutline.path(heightPt: h, centerX: geo.size.width / 2, floorY: floor)
                    // A record without a clip (the sample family): a white figure at 80 %.
                    ZStack {
                        outline.fill(Color.white.opacity(0.8))
                        outline.stroke(Theme.guide, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: record.id)
                }
                Path { p in
                    p.move(to: CGPoint(x: 0, y: floor))
                    p.addLine(to: CGPoint(x: geo.size.width, y: floor))
                }
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
            }
        }
    }
}

// MARK: R2 Lookback on the phone (Figma 223:1175)

/// Swipe sideways through the records; the clip card shows the selected one. Tapping the card
/// opens the record to change its date or height.
struct PlaybackScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let name = state.currentMember?.name ?? ""
        let records = state.currentRecords
        let index = state.recordIndex
        let record = state.selectedRecord
        let unit = state.settings.unit

        DesignCanvas(surface: .phone) {
            ScreenHeading(surface: .phone, title: Text("\(name)'s growth"),
                          subtitle: records.isEmpty ? Text("No records yet") : Text("Swipe to look back"))

            ZStack(alignment: .top) {
                RecordFigure(record: record, tallestMM: records.map(\.heightMM).max() ?? 1)
                StoryIndicator(count: records.count, index: index, width: 255)
                    .padding(.top, 13)
            }
            .frame(width: 279, height: 495)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { if let record { state.openRecord(record.id) } }
            .position(x: 201, y: 458)

            if let record {
                Text(verbatim: record.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(.english)))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .position(x: 201, y: 744)

                heightRow(records: records, index: index, unit: unit)
                    .position(x: 201, y: 790)

                Text(verbatim: growth(records: records, index: index, unit: unit))
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.hint)
                    .position(x: 201, y: 826)

                Image(systemName: "triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ink)
                    .position(x: 201, y: 862)
            }

            PhoneAppBar(back: .arrow) { state.handle(.cancel) }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                guard abs(value.translation.width) > 40 else { return }
                state.moveRecord(by: value.translation.width < 0 ? 1 : -1)
            }
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: index)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }

    /// The selected height large in the middle, its neighbours faded at the edges.
    private func heightRow(records: [GrowthRecord], index: Int, unit: HeightUnit) -> some View {
        ZStack {
            ForEach(Array(records.enumerated()), id: \.element.id) { i, record in
                let k = i - index
                let parts = HeightFormatter.parts(record.heightMM, unit: unit)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(verbatim: parts.number)
                        .font(.system(size: k == 0 ? 46 : 34, weight: k == 0 ? .bold : .regular).monospacedDigit())
                    if k == 0, let u = parts.unit {
                        Text(verbatim: u).font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundStyle(k == 0 ? Theme.ink : Theme.dialTick.opacity(0.6))
                .offset(x: CGFloat(k) * 150)
                .opacity(abs(k) > 1 ? 0 : 1)
            }
        }
        .frame(width: 402)
    }
}

/// "+5.0 cm" since the record before, or "First record".
func growth(records: [GrowthRecord], index: Int, unit: HeightUnit) -> String {
    guard records.indices.contains(index), index > 0 else { return L("First record") }
    return HeightFormatter.difference(records[index].heightMM - records[index - 1].heightMM, unit: unit)
}

// MARK: R2 Lookback on the wall (Figma 223:2213)

/// Laid over the life-size clip: title, story segments, the record's date, height and growth,
/// and a hint that goes away at the first turn of the knob or Left / Right.
struct WallPlaybackOverlay: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let name = state.currentMember?.name ?? ""
        let records = state.currentRecords
        let index = state.recordIndex
        let unit = state.settings.unit

        let hasClip = state.selectedRecord.map { state.clipURL($0) != nil } ?? false

        // The person stands life-size in the middle, so nothing covers the face: the segments sit
        // at the very top, the record at the bottom by the feet. Back is on the box.
        DesignCanvas(surface: .wall, background: .clear) {


            // Keeps the text readable over the clip's legs.
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 608, height: 300)
                .position(x: 304, y: 930)
                .opacity(hasClip ? 1 : 0)

            VStack(spacing: 4) {
                if let record = state.selectedRecord {
                    let parts = HeightFormatter.parts(record.heightMM, unit: unit)
                    Text(verbatim: record.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(.english)))
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(0.75))
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(verbatim: parts.number)
                            .font(.system(size: 58, weight: .bold).monospacedDigit())
                            .contentTransition(.numericText())
                        if let u = parts.unit {
                            Text(verbatim: u).font(.system(size: 24, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Theme.paper)
                    Text(verbatim: growth(records: records, index: index, unit: unit))
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .animation(.snappy, value: index)
            .frame(width: 608, height: 240, alignment: .bottom)
            .position(x: 304, y: 1080 - 52 - 120)

            // The segments sit under the height, at the bottom edge (the face stays clear above).
            StoryIndicator(count: records.count, index: index, width: 548, height: 4, gap: 10)
                .position(x: 304, y: 1080 - 24)

            if state.showsLookbackHint && records.count > 1 {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                    Text("Turn the knob or press \(inlineIcon(.left, size: 22)) \(inlineIcon(.right, size: 22)) to look back")
                }
                .font(Theme.label(22))
                .foregroundStyle(Theme.paper)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.18), in: Capsule())
                .position(x: 304, y: 720)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: state.showsLookbackHint)
        .allowsHitTesting(false)
    }
}
