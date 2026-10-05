import SwiftUI

/// S1: how far from the wall the projector stands for a 180 cm picture.
struct PlacementPage: View {
    @Environment(AppState.self) private var state
    @State private var custom = false

    /// A preset throw ratio, or -1 for Custom.
    private var ratioChoice: Binding<Double> {
        Binding(get: { custom ? -1 : state.settings.projector.throwRatio },
                set: { value in
                    if value < 0 {
                        custom = true
                    } else {
                        custom = false
                        state.settings.projector.throwRatio = value
                    }
                })
    }

    var body: some View {
        let projector = state.settings.projector
        Form {
            Section {
                WallCopy()
                    .frame(maxHeight: 200)
                    .frame(maxWidth: .infinity)
                    .bareListRow()
            } footer: {
                Text("The projector shows a white frame along the edge of the picture.")
            }

            Section {
                Picker("Throw ratio", selection: ratioChoice) {
                    ForEach(ProjectorSetup.presets, id: \.self) { ratio in
                        Text(String(format: "%.1f", ratio)).tag(ratio)
                    }
                    Text("Custom").tag(-1.0)
                }
                .pickerStyle(.segmented)
                if custom {
                    Stepper(value: throwRatioBinding, in: 0.3...3.0, step: 0.05) {
                        LabeledContent("Throw ratio", value: String(format: "%.2f", projector.throwRatio))
                    }
                }
            } header: {
                Text("Projector type")
            } footer: {
                Text("From the projector's manual: distance divided by picture width.")
            }

            Section("Orientation") {
                Picker("Orientation", selection: Binding(get: { projector.onItsSide },
                                                         set: { state.setProjectorOnItsSide($0) })) {
                    Text("Upright").tag(false)
                    Text("On its side").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section("Put the lens this far from the wall") {
                Text(String(format: "%.2f m", projector.distanceCM() / 100))
                    .font(.system(.largeTitle, weight: .semibold).monospacedDigit())
                LabeledContent("Picture",
                               value: L("\(Int(ProjectorSetup.targetPictureCM)) cm tall, \(Int(projector.pictureWidthCM().rounded())) cm wide"))
            }

            Section("Before fitting to the wall") {
                Label("The bottom edge of the picture must touch the floor.", systemImage: "arrow.down.to.line")
                Label("Focus, then switch off automatic keystone and autofocus.", systemImage: "scope")
                Label("Set zoom to 100 percent.", systemImage: "plus.magnifyingglass")
            }
        }
        .onAppear {
            custom = !ProjectorSetup.presets.contains(state.settings.projector.throwRatio)
        }
    }

    private var throwRatioBinding: Binding<Double> {
        Binding(get: { state.settings.projector.throwRatio },
                set: { state.settings.projector.throwRatio = ($0 * 100).rounded() / 100 })
    }
}
