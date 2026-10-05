import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @AppStorage("showVirtualController") private var showPad = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                StatusStrip()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showPad {
                    VirtualController()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showPad.toggle()
                    } label: {
                        Image(systemName: showPad ? "gamecontroller.fill" : "gamecontroller")
                    }
                    .accessibilityLabel(showPad ? "Hide on-screen controller" : "Show on-screen controller")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("Something went wrong", isPresented: errorShown) {
                Button("OK") { state.errorMessage = nil }
            } message: {
                Text(state.errorMessage ?? "")
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } })
    }

    private var title: String {
        switch state.screen {
        case .view: return "Height Ritual"
        case .playback: return "Growing up"
        case .selectChild: return "Who is measured today?"
        case .enterHeight: return "Height"
        case .capture: return "Photo"
        case .review: return "Check the photo"
        case .calibrate: return "Calibrate the wall"
        }
    }

    @ViewBuilder private var content: some View {
        switch state.screen {
        case .view, .playback: BrowseView()
        case .selectChild: SelectChildView()
        case .enterHeight: HeightEntryView()
        case .capture: CaptureView()
        case .review: ReviewView()
        case .calibrate: CalibrationView()
        }
    }
}

/// Connection status for the controller and the projector, plus the session mode.
struct StatusStrip: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            Chip(icon: "dial.medium",
                 text: "Controller: \(state.controllerStatus.label)",
                 good: state.controllerStatus == .connected)
            Chip(icon: "videoprojector",
                 text: state.externalDisplayConnected ? "Projector on" : "No projector",
                 good: state.externalDisplayConnected)
            Spacer(minLength: 0)
            if state.isRecordSession {
                Chip(icon: "record.circle", text: "Recording", good: false, tint: .red)
            }
        }
        .font(.caption)
        .padding(.top, 4)
    }
}

struct Chip: View {
    let icon: String
    let text: String
    let good: Bool
    var tint: Color? = nil

    var body: some View {
        let color = tint ?? (good ? Color.green : Color.secondary)
        Label(text, systemImage: icon)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Small copy of the projector image, so the app can be tested without a projector.
struct WallPreview: View {
    @Environment(AppState.self) private var state

    var body: some View {
        GeometryReader { geo in
            let wall = state.wallSize
            let scale = min(geo.size.width / max(wall.width, 1), geo.size.height / max(wall.height, 1))
            WallView(isExternal: false)
                .frame(width: wall.width, height: wall.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15)))
        .accessibilityLabel("Preview of the projected wall")
    }
}
