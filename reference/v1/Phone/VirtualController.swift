import SwiftUI

/// On-screen copy of the physical controller, laid out like the team sketch.
/// Sends the same events as the hardware, so every screen can be tested without it.
struct VirtualController: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(state.isRecordSession ? Color.red : Color.red.opacity(0.2))
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(state.isRecordSession ? "Recording light on" : "Recording light off")
                pad("Record", systemImage: "record.circle") { state.handle(.record) }
                pad("Playback", systemImage: "play") { state.handle(.playback) }
                Spacer(minLength: 4)
                pad("Knob left", systemImage: "arrow.counterclockwise") { state.handle(.knob(-1)) }
                pad("Knob press", systemImage: "circle.circle") { state.handle(.knobPress) }
                pad("Knob right", systemImage: "arrow.clockwise") { state.handle(.knob(1)) }
            }
            HStack(spacing: 10) {
                Button {
                    state.handle(.modeSwitch(record: !state.modeSwitchRecord))
                } label: {
                    Text(state.modeSwitchRecord ? "Mode: Record" : "Mode: View")
                        .font(.caption.weight(.medium))
                        .frame(minWidth: 96)
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 4)
                pad("Left", systemImage: "arrowtriangle.left.fill") { state.handle(.left) }
                Button {
                    state.handle(.confirm)
                } label: {
                    Image(systemName: "circle.fill").frame(width: 28, height: 20)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Confirm")
                pad("Right", systemImage: "arrowtriangle.right.fill") { state.handle(.right) }
                // On the hardware, Cancel is Confirm held for one second.
                pad("Cancel", systemImage: "xmark") { state.handle(.cancel) }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            Text("on-screen controller")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .offset(y: -14)
        }
    }

    private func pad(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(width: 28, height: 20)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }
}
