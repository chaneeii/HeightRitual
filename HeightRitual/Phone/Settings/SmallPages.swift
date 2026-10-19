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

/// Settings > Appearance: light, dark or the phone's setting. The wall image stays black.
struct AppearancePicker: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.settings
        Picker(selection: $settings.appearance) {
            Text("System").tag(Appearance.system)
            Text("Light").tag(Appearance.light)
            Text("Dark").tag(Appearance.dark)
        } label: {
            Label {
                Text("Appearance")
                Text("Light or dark phone screens. The wall stays black.")
            } icon: {
                Image(systemName: "circle.lefthalf.filled")
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
                ControllerDiagram(active: Set(testedControls.compactMap(\.control)), interactive: false)
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
                Text("Use any control on the box. While this page is open, controls are only listed here.")
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
    private var testedControls: Set<ControlCheck> {
        Set(state.controlLog.compactMap { entry in
            guard entry.note == nil, entry.bytes.count >= 2 else { return nil }
            return ControlCheck(id: entry.bytes[0], value: Int8(bitPattern: entry.bytes[1]))
        })
    }

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

/// Settings > Point colour: the colour of selection borders, the main button, the dial and the
/// saved check (`Theme.accent`). Black is the default.
struct PointColourPicker: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let current = state.settings.accentIndex
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Point colour")
                Text("Borders, buttons and the dial, on the phone and the wall")
            } icon: {
                Image(systemName: "paintpalette")
            }
            HStack(spacing: 0) {
                swatch(nil, color: Theme.ink, selected: current == nil, label: "Black")
                ForEach(Palette.memberColors.indices, id: \.self) { index in
                    swatch(index, color: Palette.color(index), selected: current == index, label: "Colour \(index + 1)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ index: Int?, color: Color, selected: Bool, label: String) -> some View {
        Button {
            state.settings.accentIndex = index
        } label: {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Color.primary, lineWidth: selected ? 3 : 0).padding(-4))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The six things to try on the box: four buttons and the knob in both directions.
private enum ControlCheck: CaseIterable {
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
