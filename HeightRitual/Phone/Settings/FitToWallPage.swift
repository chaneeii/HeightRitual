import SwiftUI

/// S2: match projected centimetres to tape marks at 0 and 100 cm on the wall.
/// The knob changes the selected value, Left / Right select, Confirm or Cancel is Done.
struct FitToWallPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        let wall = state.settings.wall

        Form {
            Section {
                WallCopy()
                    .frame(maxHeight: 320)
                    .frame(maxWidth: .infinity)
                    .bareListRow()
            } footer: {
                Text("Tape marks on the wall at 0 and 100 cm. Move the floor line until the projected 0 sits on the floor, then change the size until 100 sits on the tape. Check 150.")
            }

            Section {
                row(.floor, value: String(format: "%.0f pt", wall.floorPt),
                    binding: Binding(get: { state.settings.wall.floorPt },
                                     set: { state.settings.wall.floorPt = $0.rounded() }),
                    range: 0...600)
            } header: {
                Text(FitValue.floor.title)
            } footer: {
                Text("Moves the whole picture up or down. Set it so the projected 0 sits exactly on the floor.")
            }

            Section {
                row(.size, value: String(format: "%.2f pt/cm", wall.ptPerCM),
                    binding: Binding(get: { state.settings.wall.ptPerCM },
                                     set: { state.settings.wall.ptPerCM = ($0 * 100).rounded() / 100 }),
                    range: 1...20)
            } header: {
                Text(FitValue.size.title)
            } footer: {
                Text("Makes the centimetres on the wall bigger or smaller. Set it so the projected 100 sits on the 100 cm tape.")
            }

            Section {
                Toggle("Fine steps", isOn: $state.fitFine)
            } footer: {
                Text("Each knob turn or - / + moves 5 times less, for the last millimetres. The controller's knob changes the value in bold; Left and Right choose another one.")
            }
        }
    }

    /// One value: a slider for big moves and a stepper for single steps (the same as one knob step).
    private func row(_ value: FitValue, value text: String, binding: Binding<Double>,
                     range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper {
                Text(verbatim: text)
                    .monospacedDigit()
                    .fontWeight(state.fitValue == value ? .semibold : .regular)
            } onIncrement: {
                state.selectFitValue(value)
                state.nudgeFit(by: 1)
            } onDecrement: {
                state.selectFitValue(value)
                state.nudgeFit(by: -1)
            }
            Slider(value: binding, in: range) { editing in
                if editing { state.selectFitValue(value) }
            }
        }
        .padding(8)
        .overlay {
            // The value the knob moves; Left and Right on the controller choose it.
            if state.fitValue == value {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(SettingsStyle.highlight, lineWidth: 3)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(state.fitValue == value ? .isSelected : [])
    }
}
