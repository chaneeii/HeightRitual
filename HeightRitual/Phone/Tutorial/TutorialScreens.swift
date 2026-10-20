import SwiftUI

/// The controller box drawn on the onboarding (Figma 238:5280 and on): Back top left, the knob
/// top right, Left, Confirm and Right underneath. The controls a step uses are in colour, the rest
/// gray, and every control already learned stays filled in. The pressed control squeezes. On the
/// phone the drawing can be tapped like the box.
struct ControllerDiagram: View {
    enum Control: Hashable { case back, knob, left, right, confirm }

    let active: Set<Control>
    var learned: Set<TutorialLesson> = []
    var interactive = true
    var muted = false
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(Theme.controllerBody)
            control(.back, glyph: .back, size: 52, color: Theme.controllerBack, event: .cancel)
                .position(x: 60, y: 52)
            knob.position(x: 217, y: 52)
            control(.left, glyph: .left, size: 58, color: Theme.controllerArrow, event: .left)
                .position(x: 63, y: 144)
            control(.confirm, glyph: .confirm, size: 62, color: Theme.controllerConfirm, event: .confirm)
                .position(x: 137.5, y: 144)
            control(.right, glyph: .right, size: 58, color: Theme.controllerArrow, event: .right)
                .position(x: 212, y: 144)
        }
        .frame(width: 275, height: 195)
        .animation(.easeInOut(duration: 0.35), value: learned)
    }

    private func isOn(_ control: Control) -> Bool {
        guard !muted else { return false }
        return active.contains(control) || learned.contains(Self.lesson(control))
    }

    static func lesson(_ control: Control) -> TutorialLesson {
        switch control {
        case .back: return .back
        case .knob: return .knob
        case .left, .right: return .arrows
        case .confirm: return .confirm
        }
    }

    private func pressed(_ control: Control) -> Bool {
        switch (control, state.lastControl) {
        case (.back, .cancel?), (.left, .left?), (.right, .right?), (.confirm, .confirm?): return true
        case (.knob, .knob?): return true
        default: return false
        }
    }

    private func control(_ control: Control, glyph: ControlIcon.Glyph, size: CGFloat, color: Color,
                         event: ControlEvent) -> some View {
        let on = isOn(control)
        return Button {
            state.handle(event)
        } label: {
            Group {
                if glyph == .confirm && on {
                    ControlIcon(glyph: .confirm, size: size, confirmed: true)
                } else {
                    ControlIcon(glyph: glyph, size: size)
                        .foregroundStyle(on ? color : Theme.controllerOff)
                }
            }
            .confirmSqueeze(state.inputCount, active: on && pressed(control))
        }
        .buttonStyle(PressStyle())
        // Not `.disabled`: that would draw the icon gray (`ControlIcon` follows isEnabled).
        .allowsHitTesting(interactive)
        .accessibilityLabel(Text(verbatim: "\(control)"))
    }

    /// The knob: tap its left half to turn it back, its right half to turn it on.
    private var knob: some View {
        let on = isOn(.knob)
        return ControlIcon(glyph: .knob, size: 78)
            .foregroundStyle(on ? Theme.ink : Theme.controllerOff)
            .rotationEffect(.degrees(Double(state.inputCount % 8) * (pressed(.knob) ? 22 : 0)))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: state.inputCount)
            .overlay {
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { if interactive { state.handle(.knob(-1)) } }
                    Color.clear.contentShape(Rectangle()).onTapGesture { if interactive { state.handle(.knob(1)) } }
                }
            }
            .accessibilityLabel(Text(verbatim: "Knob"))
    }
}

/// One onboarding step, laid out on the phone's Figma frame. The wall shows the same frame,
/// scaled into its strip, with the cursor on choices and no back button (Back on the box).
struct TutorialContent: View {
    let step: TutorialStep
    var onWall = false
    @Environment(AppState.self) private var state

    var body: some View {
        let w = Surface.phone.canvas.width
        ZStack(alignment: .topLeading) {
            // Top-aligned under the bar, so a two-line title never reaches it.
            VStack(spacing: 4) {
                title.font(Theme.title(26))
                subtitle.font(Theme.subtitle(20))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.ink)
            .frame(width: w - 32)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, onWall ? 70 : 122)
            .frame(width: w, height: Surface.phone.canvas.height, alignment: .top)

            illustration
                .frame(width: w, height: 330)
                .scaleEffect(0.88)
                .position(x: w / 2, y: 415)

            if step != .ready {
                ControllerDiagram(active: active, learned: state.tutorialLearned, interactive: !onWall)
                    .position(x: w / 2, y: 698)
                // The instruction sits under the box, next to the controls it names.
                hint
                    .font(Theme.subtitle(19))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink)
                    .frame(width: w - 32)
                    .position(x: w / 2, y: 826)
            } else {
                Button { state.handle(.confirm) } label: {
                    Text("Press \(inlineIcon(.confirm, size: 18)) to begin")
                        .font(Theme.label(18))
                        .foregroundStyle(Theme.paper)
                        .frame(width: 326, height: 54)
                        .background(Theme.controllerConfirm, in: Capsule())
                }
                .buttonStyle(PressStyle())
                .allowsHitTesting(!onWall)
                .confirmSqueeze(state.confirmCount)
                .position(x: w / 2, y: 778)
            }

            if let lesson = state.tutorialToast {
                LessonToast(lesson: lesson, learnedCount: state.tutorialLearned.count)
                    .id(lesson)
                    .frame(width: w - 32)
                    .position(x: w / 2, y: onWall ? 60 : 122)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !onWall {
                TutorialBar()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: state.tutorialToast)
        .frame(width: Surface.phone.canvas.width, height: Surface.phone.canvas.height)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.menuChoice)
    }

    // MARK: Copy

    private var name: String { state.currentMember?.name ?? "" }

    private var title: Text {
        switch step {
        case .welcome: return Text("Growing up, on the wall")
        case .family: return Text("Let's start with your family")
        case .name: return Text("What is their name?")
        case .chooseRecord: return Text("Measure or look back")
        case .film: return Text("Measuring takes five seconds")
        case .height: return Text("Then check the height")
        case .saved: return Text("Back is always one step back")
        case .chooseLookback: return Text("Now look back")
        case .lookback: return Text("Look back anytime")
        case .ready: return Text("")
        }
    }

    private var subtitle: Text {
        let s: CGFloat = 18
        switch step {
        case .welcome: return Text("The marks on the doorframe,\nkept as films that move with you")
        case .family: return Text("Add someone you want to measure")
        case .name: return Text("Pick letters, then choose Save \(inlineIcon(.confirm, size: s))")
        case .chooseRecord: return Text("Press \(inlineIcon(.left, size: s)) \(inlineIcon(.right, size: s)) to choose **Record**, then \(inlineIcon(.confirm, size: s))")
        case .film: return Text("Stand inside the outline,\nfeet on the marks")
        case .height: return Text("We suggest one. You fine-tune it.")
        case .saved: return Text("Use it on any screen to leave it")
        case .chooseLookback: return Text("Press \(inlineIcon(.left, size: s)) \(inlineIcon(.right, size: s)) to choose **Lookback**, then \(inlineIcon(.confirm, size: s))")
        case .lookback: return Text("Every record plays life-size on the wall")
        case .ready: return Text("")
        }
    }

    private var hint: Text {
        let s: CGFloat = 19
        switch step {
        case .welcome: return Text("Press \(inlineIcon(.confirm, size: s)) to start")
        case .family: return Text("Press \(inlineIcon(.confirm, size: s)) to add")
        case .name: return Text("Turn the knob \(inlineIcon(.knob, size: s)) to find a letter,\npress \(inlineIcon(.confirm, size: s)) to add it")
        case .chooseRecord, .chooseLookback: return Text("Press \(inlineIcon(.left, size: s)) \(inlineIcon(.right, size: s)) to switch")
        case .film:
            if let left = state.tutorialFilmLeft { return Text("Hold still… \(left)") }
            return Text("Press \(inlineIcon(.confirm, size: s)) to film")
        case .height: return Text("Knob \(inlineIcon(.knob, size: s)) 0.1 cm, \(inlineIcon(.left, size: s)) \(inlineIcon(.right, size: s)) 1 cm,\nthen \(inlineIcon(.confirm, size: s)) to save")
        case .saved: return Text("Press \(inlineIcon(.back, size: s)) to go back")
        case .lookback: return Text("Turn the knob to step through the years,\nthen press \(inlineIcon(.confirm, size: s))")
        case .ready: return Text("")
        }
    }

    private var active: Set<ControllerDiagram.Control> {
        switch step {
        case .welcome, .family, .film: return [.confirm]
        case .name: return [.knob, .confirm]
        case .saved: return [.back]
        case .chooseRecord, .chooseLookback, .height, .lookback: return [.knob, .left, .right, .confirm]
        case .ready: return []
        }
    }

    // MARK: Illustrations

    @ViewBuilder private var illustration: some View {
        switch step {
        case .welcome: welcomeList
        case .family:
            CardFace(surface: .phone, member: nil, size: CGSize(width: 160, height: 240), isCenter: true,
                     addLabel: Text("Add member"))
                .confirmSqueeze(state.confirmCount)
        case .name:
            VStack(spacing: 56) {
                NameField(surface: .phone)
                LetterWheel(surface: .phone, onTap: { state.tapTutorialKey(at: $0) })
                    .frame(height: 110)
            }
        case .chooseRecord, .chooseLookback: choices
        case .film: filmCard
        case .height: dial
        case .saved: saved
        case .lookback: lookback
        case .ready: ready
        }
    }

    /// What the app does: an icon and a line of text each, nothing behind them.
    private var welcomeList: some View {
        VStack(alignment: .leading, spacing: 22) {
            row("video", "Film a few seconds")
            row("ruler", "Check the height")
            row("clock.arrow.circlepath", "Look back, life-size")
            row("lock", "Stays on this phone")
        }
        .frame(width: 330, height: 260)
    }

    private func row(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 32)
            Text(text).font(.system(size: 19, weight: .medium))
        }
        .foregroundStyle(Theme.ink)
    }

    private var choices: some View {
        HStack(spacing: 14) {
            choice(.record, symbol: "video.fill", label: Text("Record"))
            choice(.lookback, symbol: "play.rectangle.fill", label: Text("Lookback"))
        }
    }

    private func choice(_ action: MemberAction, symbol: String, label: Text) -> some View {
        let selected = state.menuChoice == action
        return VStack(spacing: 14) {
            Circle().fill(Theme.paper).frame(width: 74, height: 74)
                .overlay(Image(systemName: symbol).font(.system(size: 27, weight: .medium)).foregroundStyle(Theme.iconInk))
            label.font(Theme.label(18)).foregroundStyle(Theme.ink)
        }
        .frame(width: 122, height: 170)
        .background(Theme.choice, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent, lineWidth: selected ? 5 : 0))
        .overlay(alignment: .bottomTrailing) {
            if selected {
                CursorView(size: 40, trigger: action)
                    .offset(x: 14, y: 16)
            }
        }
        .confirmSqueeze(state.confirmCount, active: selected)
        .zIndex(selected ? 1 : 0)
        .onTapGesture {
            guard !onWall else { return }
            if state.menuChoice == action { state.handle(.confirm) } else { state.handle(action == .record ? .left : .right) }
        }
    }

    private var filmCard: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black
            FootGuideOverlay(guide: FootGuide.make(camera: nil, outlineMM: FootGuide.firstRecordMM), accent: Theme.guide)
            if let left = state.tutorialFilmLeft {
                Text(verbatim: "\(left)")
                    .font(.system(size: 52, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.paper)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: left)
                    .padding(.trailing, 16)
                    .padding(.bottom, 40)
            }
        }
        .frame(width: 172, height: 306)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottom) {
            if state.tutorialFilmLeft != nil {
                FilmProgressBar(width: 172, height: 6, track: Color(white: 0.3), fill: Theme.paper)
                    .offset(y: 18)
            }
        }
    }

    private var dial: some View {
        let mm = state.tutorialMM
        let reached = mm == 1245
        let parts = HeightFormatter.parts(mm, unit: state.settings.unit)
        return VStack(spacing: 14) {
            HStack(spacing: 6) {
                Text("Try setting it to 124.5 cm")
                if reached {
                    ControlIcon(glyph: .confirm, size: 20, confirmed: true)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .font(.system(size: 17))
            .animation(.spring, value: reached)
            ZStack(alignment: .top) {
                HeightDial(surface: .phone, valueCM: Double(mm) / 10, width: 402, height: 180)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: mm)
                VStack(spacing: 0) {
                    Text(verbatim: parts.number)
                        .font(.system(size: 52, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.snappy, value: mm)
                    if let unit = parts.unit { Text(verbatim: unit).font(.system(size: 18)) }
                }
                .padding(.top, 108)
            }
            // The same dial as the real height check, full width.
            .frame(width: 402, height: 180)
        }
    }

    private var saved: some View {
        let height = state.savedRecord.map { HeightFormatter.text($0.heightMM, unit: state.settings.unit) } ?? ""
        return VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.accent)
                CheckShape().stroke(Theme.paper, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .frame(width: 38, height: 28)
            }
            .frame(width: 82, height: 82)
            Text("Saved").font(Theme.title(24))
            Text("\(name)'s height is now \(height)").font(Theme.subtitle(18))
            Button { state.handle(.cancel) } label: {
                HStack(spacing: 4) {
                    Text("Back")
                    if onWall {
                        Text(verbatim: "(")
                        ControlIcon(glyph: .back, size: 18).foregroundStyle(Theme.paper)
                        Text(verbatim: ")")
                    }
                }
                .font(Theme.label(18))
                .foregroundStyle(Theme.paper)
                .frame(width: 310, height: 50)
                .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(PressStyle())
            .allowsHitTesting(!onWall)
            .padding(.top, 14)
        }
        .foregroundStyle(Theme.ink)
    }

    private var lookback: some View {
        let records = state.currentRecords
        let unit = state.settings.unit
        return ZStack(alignment: .top) {
            RecordFigure(record: state.selectedRecord, tallestMM: records.map(\.heightMM).max() ?? 1, share: 0.6)
            VStack(spacing: 6) {
                StoryIndicator(count: records.count, index: state.recordIndex, width: 166)
                    .padding(.top, 10)
                if let record = state.selectedRecord {
                    let parts = HeightFormatter.parts(record.heightMM, unit: unit)
                    Text(verbatim: record.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(.english)))
                        .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.7))
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text(verbatim: parts.number).font(.system(size: 26, weight: .bold))
                        if let u = parts.unit { Text(verbatim: u).font(.system(size: 11, weight: .semibold)) }
                    }
                    .foregroundStyle(Theme.paper)
                    Text(verbatim: growth(records: records, index: state.recordIndex, unit: unit))
                        .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.7))
                }
            }
        }
        .frame(width: 190, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var ready: some View {
        VStack(spacing: 24) {
            // Everything learned: the whole box in colour.
            ControllerDiagram(active: [], learned: state.tutorialLearned, interactive: false)
                .scaleEffect(0.72)
                .frame(width: 198, height: 140)
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("You're ready").font(Theme.title(26))
                    Image(systemName: "party.popper").font(.system(size: 24))
                }
                Text("Let's measure someone today").font(Theme.subtitle(19))
            }
        }
        .foregroundStyle(Theme.ink)
        .offset(y: 40)
    }
}

/// "You learned Confirm!": a banner that drops in at the top the first time a control is used,
/// with the control in its colour and how many of the four are learned.
private struct LessonToast: View {
    let lesson: TutorialLesson
    let learnedCount: Int

    var body: some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 52, height: 52)
                .background(Theme.paper.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(Theme.label(19))
                    .foregroundStyle(Theme.paper)
                Text("\(min(learnedCount, TutorialLesson.allCases.count)) of \(TutorialLesson.allCases.count) controls learned")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.paper.opacity(0.6))
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(0..<TutorialLesson.allCases.count, id: \.self) { index in
                    Circle()
                        .fill(index < learnedCount ? Theme.success : Theme.paper.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        switch lesson {
        case .confirm: return "You learned Confirm!"
        case .knob: return "You learned the knob!"
        case .arrows: return "You learned Left and Right!"
        case .back: return "You learned Back!"
        }
    }

    @ViewBuilder private var icon: some View {
        switch lesson {
        case .confirm: ControlIcon(glyph: .confirm, size: 30, confirmed: true)
        case .knob: ControlIcon(glyph: .knob, size: 32).foregroundStyle(Theme.paper)
        case .arrows:
            HStack(spacing: 1) {
                ControlIcon(glyph: .left, size: 20)
                ControlIcon(glyph: .right, size: 20)
            }
            .foregroundStyle(Theme.controllerArrow)
        case .back: ControlIcon(glyph: .back, size: 28).foregroundStyle(Theme.controllerBack)
        }
    }
}

/// The phone's bar on the onboarding: Back on the left; debug and Close on the right.
private struct TutorialBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            Button { state.handle(.cancel) } label: {
                Image(systemName: "arrow.left").font(.system(size: 22)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
            Spacer()
            DebugWallButton()
            Button { state.endTutorial() } label: {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .frame(width: Surface.phone.canvas.width, height: 44)
        .position(x: Surface.phone.canvas.width / 2, y: 61.5 + 22 + 6)
    }
}

/// The onboarding on the phone.
struct TutorialScreen: View {
    let step: TutorialStep

    var body: some View {
        DesignCanvas(surface: .phone) {
            TutorialContent(step: step)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: step)
    }
}
