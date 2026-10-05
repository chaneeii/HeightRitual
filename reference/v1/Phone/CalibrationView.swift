import SwiftUI

/// Installation step: a ruler is projected; match it to a real tape measure on the wall.
struct CalibrationView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        let top = state.calibration.visibleTopCM(for: state.wallSize)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Tape marks on the wall at 0 cm (floor) and 100 cm, measured with a real tape.")
                    Text("2. Move the floor line until the projected 0 sits on the floor.")
                    Text("3. Change the scale until the projected 100 sits on your 100 cm mark.")
                    Text("4. Check 150 cm with the tape. The image must reach at least 170 cm.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Label("Visible from the floor up to \(Int(top)) cm",
                      systemImage: top >= 170 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(top >= 170 ? .green : .orange)
                    .font(.headline)

                Picker("Projector", selection: $state.calibration.rotation) {
                    Text("Upright").tag(0)
                    Text("On its side, left").tag(-90)
                    Text("On its side, right").tag(90)
                }
                .pickerStyle(.segmented)

                CalibrationRow(param: .floor, value: $state.calibration.floorPt, range: 0...600,
                               unit: "pt", format: "%.0f")
                CalibrationRow(param: .scale, value: $state.calibration.ptPerCM, range: 1...20,
                               unit: "pt per cm", format: "%.2f")
                CalibrationRow(param: .shift, value: $state.calibration.shiftPt, range: -600...600,
                               unit: "pt", format: "%.0f")

                Text("On the controller: Left and Right choose the setting, the knob changes it, pressing the knob switches fine steps \(state.calibrationFine ? "off" : "on"), Confirm finishes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Reset") { state.calibration = Calibration(); state.calibration.save() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Done") { state.finishCalibration() }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding(.vertical, 8)
        }
        .onChange(of: state.calibration) { _, value in value.save() }
    }
}

private struct CalibrationRow: View {
    @Environment(AppState.self) private var state
    let param: CalibrationParam
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let format: String

    var body: some View {
        let active = state.calibrationParam == param
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(param.title).font(.subheadline.weight(active ? .semibold : .regular))
                Spacer()
                Text("\(String(format: format, value)) \(unit)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button { state.calibrationParam = param; state.nudgeCalibration(by: -1) } label: { Image(systemName: "minus") }
                    .accessibilityLabel("Decrease \(param.title)")
                Slider(value: $value, in: range)
                Button { state.calibrationParam = param; state.nudgeCalibration(by: 1) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Increase \(param.title)")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(active ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture { state.calibrationParam = param }
    }
}
