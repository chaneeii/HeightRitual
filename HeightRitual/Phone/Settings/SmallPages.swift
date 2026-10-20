import SwiftUI

/// S4: centimetres or feet and inches (stored heights never change). Choosing one saves it and
/// goes back to the list, the same as Select on the projector's Units page.
struct UnitsPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section {
                Picker("Units", selection: Binding(get: { state.settings.unit },
                                                   set: { state.chooseUnit($0) })) {
                    LabeledContent("Centimetres", value: HeightFormatter.text(1210, unit: .cm)).tag(HeightUnit.cm)
                    LabeledContent("Feet and inches", value: HeightFormatter.text(1210, unit: .ftin)).tag(HeightUnit.ftin)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Every height on the phone and the wall follows this. Stored heights do not change.")
            }
        }
    }
}

/// S6: connection state, a live list of what the controller sends (to test the box), a light
/// test and Forget this controller. While this page is open, controls are only listed.
struct ControllerPage: View {
    @Environment(AppState.self) private var state
    @State private var confirmForget = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: state.controllerStatus == .connected
                               ? L("Connected") : state.controllerStatus.label)
                LabeledContent("Last control used", value: state.lastControl?.label ?? L("None yet"))
            }

            Section {
                PressedControllerDiagram()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                ForEach(ControlCheck.allCases, id: \.self) { check in
                    LabeledContent {
                        Image(systemName: testedControls.contains(check) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(testedControls.contains(check) ? Theme.success : Color.secondary)
                    } label: {
                        Text(verbatim: check.title)
                    }
                }
            } header: {
                Text("Test each control")
            } footer: {
                Text("Press every button and turn the knob both ways on the box. Each one turns green once the app has received it. Clear list starts again.")
            }

            Section {
                if state.controlLog.isEmpty {
                    Text("Nothing yet").foregroundStyle(.secondary)
                }
                ForEach(state.controlLog.prefix(12)) { entry in
                    LabeledContent {
                        Text(entry.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()
                            .secondFraction(.fractional(2))))
                    } label: {
                        Text(entry.text)
                    }
                    .font(.callout.monospacedDigit())
                }
                if !state.controlLog.isEmpty {
                    Button("Clear list") { state.clearControlLog() }
                }
            } header: {
                Text("Received")
            } footer: {
                Text("Use any control on the box. While this page is open, controls are only listed here; Back twice on the box goes back.")
            }

            Section {
                HStack(spacing: 8) {
                    lightButton("Blink", .countdown)
                    lightButton("On", .steady)
                    lightButton("Flash", .saved)
                    lightButton("Off", .off)
                }
            } header: {
                Text("Recording light")
            } footer: {
                Text("The light on the controller follows these while it is connected.")
            }

            Section {
                Button("Forget this controller", role: .destructive) { confirmForget = true }
            } footer: {
                Text("The controller connects by itself when it is switched on. Every control also works with the buttons on this phone.")
            }
        }
        .confirmationDialog("Forget this controller?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) { state.forgetController() }
        } message: {
            Text("The app searches again and connects to the first Memory Meter controller it finds.")
        }
    }

    /// What the box has sent since the list was cleared, from the raw packets (SPEC 6).
    private var testedControls: Set<ControlCheck> { state.testedControls }

    private func lightButton(_ title: LocalizedStringKey, _ recording: LightState.Recording) -> some View {
        Button(title) { state.testLight(recording) }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(state.controllerStatus != .connected)
    }
}

/// Settings > Setup guide: where the projector and the phone stand, as two pictures with the
/// same steps written out below, readable at phone size. Tapping a picture shows it full size.
struct SetupGuidePage: View {
    private struct Step: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        let picture: String
        let description: LocalizedStringKey
    }

    private let steps = [
        Step(id: "projector", title: "1. Place the projector",
             text: "Put the projector 2.5 m from the wall, with the centre of the lens 0.97 m above the floor. The bottom edge of the picture should touch the floor.",
             picture: "SetupGuideProjector",
             description: "The projector on a stand 2.5 m from the wall, lens around 0.97 m above the floor. A child stands against the wall in the light."),
        Step(id: "camera", title: "2. Place the phone next to it",
             text: "Put the phone right next to the projector, also 2.5 m from the wall and about 0.97 m above the floor. Stand it upright with the rear camera facing the wall. The parent stands behind them with the controller.",
             picture: "SetupGuideCamera",
             description: "Seen from above and from the side: the phone on a tripod next to the projector, 2.5 m from the wall, camera about 0.97 m above the floor. A parent stands behind them with the controller."),
    ]
    @State private var enlarged: String?

    var body: some View {
        Form {
            ForEach(steps) { step in
                Section {
                    Button {
                        enlarged = step.picture
                    } label: {
                        Image(step.picture)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(step.description))
                    .accessibilityHint("Shows the picture full size")
                    Text(step.text)
                } header: {
                    Text(step.title)
                } footer: {
                    Label("Tap the picture to see it full size", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
        }
        .fullScreenCover(item: Binding(get: { enlarged.map(EnlargedPicture.init) },
                                       set: { enlarged = $0?.id })) { picture in
            EnlargedPictureView(name: picture.id)
        }
    }
}

private struct EnlargedPicture: Identifiable {
    let id: String
}

/// One setup picture at twice the screen width, panned with the finger; Done closes it.
private struct EnlargedPictureView: View {
    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    Image(name)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width * 2.4)
                }
                .defaultScrollAnchor(.center)
            }
            .background(Color(red: 0.965, green: 0.969, blue: 0.976))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Settings > Sound: on or off. Choosing one saves it and goes back to the list, the same as
/// Select on the projector's Sound page.
struct SoundPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section {
                Picker("Sound", selection: Binding(get: { state.settings.soundOn },
                                                   set: { state.chooseSound($0) })) {
                    Text("On").tag(true)
                    Text("Off").tag(false)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Record and play sound with each clip")
            }
        }
    }
}

/// Settings > Point colour: Black or one of the palette colours, for borders, buttons and the dial on
/// the phone and the wall. Choosing one saves it and goes back to the list, the same as Select on
/// the projector's Point colour page.
struct PointColourPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section {
                ForEach(AppState.pointColours, id: \.self) { index in
                    Button {
                        state.choosePointColour(index)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(index.map(Palette.color) ?? Theme.ink)
                                .frame(width: 26, height: 26)
                            Text(verbatim: index.map { "Colour \($0 + 1)" } ?? "Black")
                            Spacer()
                            if state.settings.accentIndex == index {
                                Image(systemName: "checkmark").fontWeight(.semibold)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(state.settings.accentIndex == index ? .isSelected : [])
                }
            } footer: {
                Text("Borders, buttons and the dial, on the phone and the wall")
            }
        }
    }
}

/// The six things to try on the box: four buttons and the knob in both directions.
enum ControlCheck: CaseIterable {
    case back, knobClockwise, knobCounterclockwise, left, confirm, right

    init?(id: UInt8, value: Int8) {
        switch id {
        case 23: self = .back
        case 1 where value > 0: self = .knobClockwise
        case 1 where value < 0: self = .knobCounterclockwise
        case 14: self = .left
        case 13: self = .confirm
        case 15: self = .right
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .back: return "Back"
        case .knobClockwise: return "Knob clockwise"
        case .knobCounterclockwise: return "Knob counter-clockwise"
        case .left: return "Left"
        case .confirm: return "Confirm"
        case .right: return "Right"
        }
    }

    var control: ControllerDiagram.Control? {
        switch self {
        case .back: return .back
        case .knobClockwise, .knobCounterclockwise: return .knob
        case .left: return .left
        case .confirm: return .confirm
        case .right: return .right
        }
    }
}

extension AppState {
    /// The controls the box has sent since the list was last cleared.
    var testedControls: Set<ControlCheck> {
        Set(controlLog.compactMap { entry in
            guard entry.note == nil, entry.bytes.count >= 2 else { return nil }
            return ControlCheck(id: entry.bytes[0], value: Int8(bitPattern: entry.bytes[1]))
        })
    }
}

/// What Load sample family and Delete everything ask, on the phone and the projector.
struct SettingsQuestion {
    let title: String
    let message: String
    let action: String

    @MainActor static func current(_ state: AppState) -> SettingsQuestion? {
        switch state.route {
        case .settings(.confirmSample):
            return SettingsQuestion(
                title: "Load the sample family?",
                message: "Every member, record and clip on this phone is replaced by Nora and Leo.",
                action: "Replace with sample family")
        case .settings(.confirmDelete) where state.deleteStep == 1:
            return SettingsQuestion(
                title: "Delete everything?",
                message: "Removes every member, record and clip. Setup values are kept.",
                action: "Delete everything")
        case .settings(.confirmDelete):
            return SettingsQuestion(
                title: "Are you sure?",
                message: "This cannot be undone. Every member, record and clip is deleted.",
                action: "Delete everything")
        default:
            return nil
        }
    }
}

/// Settings > Load sample family or Delete everything on the phone: the question, the action and
/// Cancel. The projector asks the same; the answer is the same from either.
struct SettingsQuestionPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let question = SettingsQuestion.current(state) {
            Form {
                Section {
                    Text(verbatim: question.title).font(.headline)
                    Text(verbatim: question.message).foregroundStyle(.secondary)
                }
                Section {
                    Button(role: .destructive) { state.answerQuestion(true) } label: {
                        Text(verbatim: question.action)
                    }
                    Button("Cancel") { state.answerQuestion(false) }
                }
            }
        }
    }
}

/// The controller box on the Controller test pages (phone and projector): the control just pressed
/// lights up for a moment. The list below it keeps which controls have been received.
struct PressedControllerDiagram: View {
    @Environment(AppState.self) private var state
    @State private var lit: ControllerDiagram.Control?

    var body: some View {
        ControllerDiagram(active: lit.map { [$0] } ?? [], interactive: false)
            .onChange(of: state.inputCount) {
                let pressed = state.lastControl.flatMap(Self.control)
                lit = pressed
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    if lit == pressed { lit = nil }
                }
            }
    }

    private static func control(_ event: ControlEvent) -> ControllerDiagram.Control? {
        switch event {
        case .cancel: return .back
        case .knob: return .knob
        case .left: return .left
        case .right: return .right
        case .confirm: return .confirm
        default: return nil
        }
    }
}
