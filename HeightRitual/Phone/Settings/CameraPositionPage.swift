import SwiftUI

/// S3: tells the app where the wall's floor line and 100 cm line are in the camera picture.
/// The wall shows two bright lines; the user drags the two lines in the preview onto them.
struct CameraPositionPage: View {
    @Environment(AppState.self) private var state
    @State private var floorY = 0.85
    @State private var y100 = 0.45
    @State private var centerX = 0.5
    @State private var saved = false

    /// One step of the steppers, as a fraction of the frame height (about 2 px of 1920).
    private let step = 0.001

    var body: some View {
        Form {
            Section {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        CameraPreview(session: state.cameraSession)
                        line("Floor", y: floorY, height: geo.size.height)
                        line("100 cm", y: y100, height: geo.size.height)
                    }
                    .contentShape(Rectangle())
                    // Drag anywhere: the nearer line follows the finger.
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { drag in
                        let y = Double(drag.location.y / geo.size.height)
                        if abs(y - floorY) <= abs(y - y100) {
                            floorY = min(max(y, y100 + 0.05), 0.99)
                        } else {
                            y100 = max(min(y, floorY - 0.05), 0.01)
                        }
                    })
                }
                .aspectRatio(FootGuide.frameAspect, contentMode: .fit)
                .frame(maxHeight: 460)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .bareListRow()
            } footer: {
                Text("The wall shows two bright lines, at the floor and at 100 cm. Drag the two lines in the camera picture onto them.")
            }

            Section("Floor line") {
                Stepper(value: $floorY, in: (y100 + 0.05)...0.99, step: step) {
                    Text(percent(floorY)).monospacedDigit()
                }
            }
            Section {
                Stepper(value: $y100, in: 0.01...(floorY - 0.05), step: step) {
                    Text(percent(y100)).monospacedDigit()
                }
            } header: {
                Text("100 cm line")
            } footer: {
                Text("Position in the camera picture, measured from its top edge. Each step is about 2 pixels.")
            }

            Section {
                // The one next action on this page: a full-width prominent button.
                BigButton(title: saved ? "Saved" : "Save position",
                          systemImage: saved ? "checkmark" : nil, prominent: true) {
                    state.saveCameraPosition(CameraPosition(floorY: floorY, y100: y100, centerX: centerX))
                    saved = true
                }
                .disabled(saved)
                .bareListRow()
            } footer: {
                Text("Valid only while the phone stays on its stand. Moving the phone means doing this again.")
            }
        }
        .onAppear {
            if let camera = state.settings.camera {
                floorY = min(max(camera.floorY, 0.06), 0.99)
                y100 = min(max(camera.y100, 0.01), floorY - 0.05)
                centerX = camera.centerX
            }
        }
        .onChange(of: floorY) { saved = false }
        .onChange(of: y100) { saved = false }
    }

    private func percent(_ value: Double) -> String {
        let amount = String(format: "%.1f %%", value * 100)
        return L("\(amount) from top")
    }

    private func line(_ title: String, y: Double, height: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            Rectangle().fill(Color.yellow).frame(height: 2)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow, in: Capsule())
                .padding(.trailing, 8)
        }
        .frame(height: 24)
        .offset(y: y * height - 12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
