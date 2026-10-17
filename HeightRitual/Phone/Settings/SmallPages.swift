import SwiftUI

/// S4: centimetres or feet and inches (stored heights never change), and the phone's appearance.
struct UnitsPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.settings
        Form {
            Section {
                Picker("Units", selection: $settings.unit) {
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
            Text("The app searches again and connects to the first Height Ritual controller it finds.")
        }
    }

    private func lightButton(_ title: LocalizedStringKey, _ recording: LightState.Recording) -> some View {
        Button(title) { state.testLight(recording) }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(state.controllerStatus != .connected)
    }
}

/// Settings > Language: a dropdown like Appearance. The change applies at once, on the phone
/// and the wall.
struct LanguagePicker: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.settings
        Picker(selection: $settings.language) {
            Text("System").tag(AppLanguage.system)
            ForEach(AppLanguage.allCases.filter { $0 != .system }, id: \.self) { language in
                Text(verbatim: language.nativeName).tag(language)
            }
        } label: {
            Label {
                Text("Language")
                Text("For the phone and the wall")
            } icon: {
                Image(systemName: "globe")
            }
        }
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
