import SwiftUI

// MARK: M2 film: before and while filming (Figma 223:347, 223:684; wall 223:1914, 223:1983)

/// The phone while filming: the camera picture with the outline to stand in, Record, then a bar
/// that fills over the five seconds. There is no countdown: Record films at once.
struct FilmScreen: View {
    let film: FilmState
    @Environment(AppState.self) private var state

    var body: some View {
        let name = state.currentMember?.name ?? ""
        let filming = film != .ready

        DesignCanvas(surface: .phone) {
            ScreenHeading(surface: .phone,
                          title: filming ? Text("Recording…") : Text("Measure \(name)"),
                          subtitle: filming ? Text("Hold still for a few seconds")
                                            : Text("Stand inside the outline, feet on the marks."))

            camera
                .position(x: 201, y: 500)

            if filming {
                FilmProgressBar(width: 336, height: 18)
                    .position(x: 201, y: 808)
            } else {
                PillButton(surface: .phone, title: Text("Record"), systemImage: "record.circle",
                           style: .record, size: CGSize(width: 186, height: 68)) {
                    state.handle(.record)
                }
                .position(x: 201, y: 811)
            }

            PhoneAppBar(back: .arrow) { state.handle(.cancel) }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }

    @ViewBuilder private var camera: some View {
        let size = CGSize(width: 293, height: 520)
        ZStack(alignment: .bottomTrailing) {
            if CameraController.isRefused {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash").font(.system(size: 34))
                    Text("Memory Meter needs the camera to film the clip.")
                        .multilineTextAlignment(.center)
                    Button("Open permissions") {
                        state.openSettings()
                        state.openSettingsPage(.permissions)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(Theme.paper)
                .padding()
                .frame(width: size.width, height: size.height)
                .background(Color.black)
            } else {
                CameraPreview(session: state.cameraSession)
                FootGuideOverlay(guide: state.footGuide, accent: Theme.guide)
            }
            if case .filming(let left) = film {
                Text(verbatim: "\(left)")
                    .font(.system(size: 64, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.paper)
                    .padding(.trailing, 22)
                    .padding(.bottom, 64)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: left)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The wall while filming, laid over the life-size outline: the title and Record, then the bar
/// and the seconds left.
struct WallFilmOverlay: View {
    let film: FilmState
    @Environment(AppState.self) private var state

    var body: some View {
        let name = state.currentMember?.name ?? ""
        DesignCanvas(surface: .wall, background: .clear) {
            switch film {
            case .ready:
                ScreenHeading(surface: .wall, title: Text("Measure \(name)"),
                              subtitle: Text("Stand inside the outline, feet on the marks.\nPress \(inlineIcon(.confirm, size: 30)) to start recording"),
                              onDark: true, top: 160)
                PillButton(surface: .wall, title: Text("Record"), systemImage: "record.circle",
                           style: .record, size: CGSize(width: 240, height: 86))
                    .position(x: 304, y: 380)
                    .confirmSqueeze(state.confirmCount)
            case .filming(let left):
                FilmProgressBar(width: 488, height: 17, track: Color(white: 0.3), fill: Theme.paper)
                    .position(x: 304, y: 61)
                Text("Recording… hold still (\(left)s)")
                    .font(Theme.label(24))
                    .foregroundStyle(Theme.paper)
                    .position(x: 304, y: 105)
                Text(verbatim: "\(left)")
                    .font(.system(size: 96, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.paper)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: left)
                    .position(x: 510, y: 985)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: M3 height (Figma 223:838, 223:2071)

/// Checking the height: the clip (or the outline at the dial's height), the dial, Retake and Save.
/// Knob: 0.1 cm a step, Left / Right: 1 cm; on the phone the dial is dragged.
struct HeightContent: View {
    let surface: Surface
    let height: HeightState
    @Environment(AppState.self) private var state
    @State private var dragStartMM: Int?

    var body: some View {
        let w = surface.canvas.width
        ZStack(alignment: .topLeading) {
            switch height {
            case .cuttingOut(let progress):
                ScreenHeading(surface: surface, title: Text("Preparing the clip"),
                              subtitle: Text("This takes a few seconds"))
                ProgressView(value: progress)
                    .tint(Theme.accent)
                    .frame(width: surface.v(260, 380))
                    .scaleEffect(y: 2)
                    .position(x: w / 2, y: surface.v(440, 560))
                retake(primary: true, single: true)

            case .noPerson:
                ScreenHeading(surface: surface, title: Text("Nobody found in the video"),
                              subtitle: Text("Stand with your heels on the line and film again."))
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: surface.v(80, 120)))
                    .foregroundStyle(Theme.iconInk)
                    .position(x: w / 2, y: surface.v(420, 540))
                if state.draft?.clip.rawVideoURL != nil {
                    // Testing without a person: the clip is kept as filmed, the height set by hand.
                    PillButton(surface: surface, title: Text("Use this clip anyway"), style: .secondary,
                               size: buttonSize(single: true)) { state.useClipWithoutPerson() }
                        .position(x: w / 2, y: surface.v(745, 905))
                }
                retake(primary: true, single: true)

            case .editing:
                editing
            }

            if surface == .phone {
                PhoneAppBar(back: .arrow) { state.handle(.cancel) }
            }
        }
        .frame(width: surface.canvas.width, height: surface.canvas.height)
        .animation(.easeOut(duration: 0.3), value: state.settings.heightStepsLearned)
    }

    @ViewBuilder private var editing: some View {
        let name = state.currentMember?.name ?? ""
        let mm = state.draft?.heightMM ?? HeightFormatter.emptyFieldStartMM
        let w = surface.canvas.width
        let parts = HeightFormatter.parts(mm, unit: state.settings.unit)
        let dialTop = surface.v(577, 694), dialHeight = surface.v(180, 250)

        ScreenHeading(surface: surface, title: Text("Check \(name)'s height"),
                      subtitle: surface == .phone ? Text("Drag the dial to adjust, then tap Save")
                              : state.settings.heightStepsLearned ? Text("Turn the knob to fine-tune") : stepHint,
                      top: surface.v(121, 100))

        DraftPreview(size: surface.s(CGSize(width: 178, height: 318), CGSize(width: 236, height: 420)))
            .position(x: w / 2, y: surface.v(384, 470))

        HeightDial(surface: surface, valueCM: Double(mm) / 10, width: w, height: dialHeight)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: mm)
            .position(x: w / 2, y: dialTop + dialHeight / 2)
            .gesture(dialDrag, including: surface == .phone ? .all : .subviews)

        VStack(spacing: 0) {
            Text(verbatim: parts.number)
                .font(.system(size: parts.unit == nil ? surface.v(30, 40) : surface.v(52, 68), weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.snappy, value: mm)
            if let unit = parts.unit {
                Text(verbatim: unit).font(.system(size: surface.v(18, 26)))
            }
        }
        .foregroundStyle(Theme.ink)
        .position(x: w / 2, y: dialTop + surface.v(146, 205))

        retake(primary: false, single: false)
        PillButton(surface: surface, title: Text("Save"), control: .confirm, style: .primary,
                   size: buttonSize(single: false)) { state.handle(.confirm) }
            .confirmSqueeze(state.confirmCount, active: surface == .wall)
            .position(x: surface.v(296.5, 448), y: surface.v(825, 1000))
    }

    /// Wall, first use only, until the knob or Left / Right is used: how big each step is.
    private var stepHint: Text {
        let icon: CGFloat = 26
        let fine = state.settings.unit == .cm ? "0.1 cm" : "1/4 in"
        let coarse = state.settings.unit == .cm ? "1 cm" : "1 in"
        return Text("Turn \(inlineIcon(.knob, size: icon)) for \(fine), press \(inlineIcon(.left, size: icon)) \(inlineIcon(.right, size: icon)) for \(coarse)")
    }

    private func retake(primary: Bool, single: Bool) -> some View {
        PillButton(surface: surface, title: Text("Retake"), control: .back,
                   style: primary ? .primary : .secondary, size: buttonSize(single: single)) {
            state.handle(.cancel)
        }
        .position(x: single ? surface.canvas.width / 2 : surface.v(105.5, 160),
                  y: single ? surface.v(815, 1000) : surface.v(825, 1000))
    }

    private func buttonSize(single: Bool) -> CGSize {
        single ? surface.s(CGSize(width: 340, height: 56), CGSize(width: 520, height: 80))
               : surface.s(CGSize(width: 171, height: 56), CGSize(width: 260, height: 80))
    }

    /// Phone: drag the scale sideways; the arc follows the finger.
    private var dialDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStartMM ?? state.draft?.heightMM ?? HeightFormatter.emptyFieldStartMM
                if dragStartMM == nil { dragStartMM = start }
                let radius: Double = 176
                let degrees = -Double(value.translation.width) / radius * 180 / .pi
                let mm = start + Int((degrees / HeightDial.degreesPerCM * 10).rounded())
                state.setDraftHeight(mm)
            }
            .onEnded { _ in dragStartMM = nil }
    }
}

struct HeightScreen: View {
    let height: HeightState

    var body: some View {
        DesignCanvas(surface: .phone) {
            HeightContent(surface: .phone, height: height)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }
}

// MARK: M4 saved (Figma 223:1017, 223:2150)

/// Saved: the check draws itself, then See growth (Confirm) or Return to home (Cancel).
struct SavedContent: View {
    let surface: Surface
    @Environment(AppState.self) private var state
    @State private var shown = false

    var body: some View {
        let w = surface.canvas.width
        let name = state.currentMember?.name ?? ""
        let height = state.savedRecord.map { HeightFormatter.text($0.heightMM, unit: state.settings.unit) } ?? ""
        let d = surface.v(111, 182.6)

        ZStack(alignment: .topLeading) {
            ZStack {
                Circle().fill(Theme.success)
                    .scaleEffect(shown ? 1 : 0.3)
                    .opacity(shown ? 1 : 0)
                CheckShape()
                    .trim(from: 0, to: shown ? 1 : 0)
                    .stroke(Theme.paper, style: StrokeStyle(lineWidth: d * 0.09, lineCap: .round, lineJoin: .round))
                    .frame(width: d * 0.46, height: d * 0.34)
                    .animation(.easeOut(duration: 0.4).delay(0.25), value: shown)
            }
            .frame(width: d, height: d)
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: shown)
            .position(x: w / 2, y: surface.v(329.5, 377.4))

            Text("Saved")
                .font(Theme.title(surface.v(26, 40)))
                .position(x: w / 2, y: surface.v(420, 523))
            Text("\(name)'s height is now \(height)")
                .font(Theme.subtitle(surface.v(19, 30)))
                .position(x: w / 2, y: surface.v(460, 587))

            PillButton(surface: surface, title: Text("See \(name)'s growth"), control: .confirm,
                       style: .primary, size: surface.s(CGSize(width: 340, height: 56), CGSize(width: 533, height: 86))) {
                state.seeGrowth()
            }
            .confirmSqueeze(state.confirmCount, active: surface == .wall)
            .position(x: w / 2, y: surface.v(738, 896))

            PillButton(surface: surface, title: Text("Return to home"), control: .back,
                       style: .secondary, size: surface.s(CGSize(width: 340, height: 56), CGSize(width: 533, height: 86))) {
                state.measureSomeoneElse()
            }
            .position(x: w / 2, y: surface.v(808, 1007))
        }
        .foregroundStyle(Theme.ink)
        .frame(width: surface.canvas.width, height: surface.canvas.height)
        .onAppear { shown = true }
    }
}

/// The tick of the saved check, drawn left to right.
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct SavedScreen: View {
    var body: some View {
        DesignCanvas(surface: .phone) {
            SavedContent(surface: .phone)
            PhoneAppBar()
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }
}
