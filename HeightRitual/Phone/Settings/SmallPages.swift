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
