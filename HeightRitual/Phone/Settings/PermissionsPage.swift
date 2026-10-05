import AVFoundation
import CoreBluetooth
import SwiftUI
import UIKit

/// S5: camera, Bluetooth and (with sound on) microphone. Asks when not asked yet; otherwise
/// opens iOS Settings, the only place a refused permission can be changed.
struct PermissionsPage: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = 0

    enum Access { case notAsked, allowed, refused }

    var body: some View {
        Form {
            Section {
                row("Camera", why: "Films the clip.", access: camera) {
                    AVCaptureDevice.requestAccess(for: .video) { _ in Task { @MainActor in refresh += 1 } }
                }
                row("Bluetooth", why: "Connects the controller.", access: bluetooth) {
                    state.startController()
                    // The answer arrives through the central manager; check again shortly.
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        refresh += 1
                    }
                }
                if state.settings.soundOn {
                    row("Microphone", why: "Records sound with the clip.", access: microphone) {
                        AVAudioApplication.requestRecordPermission { _ in Task { @MainActor in refresh += 1 } }
                    }
                }
            } footer: {
                Text("Nothing leaves this phone. Clips are stored only in the app.")
            }
        }
        .id(refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh += 1 }
        }
    }

    private var camera: Access {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notAsked
        case .authorized: return .allowed
        default: return .refused
        }
    }

    private var bluetooth: Access {
        switch CBManager.authorization {
        case .notDetermined: return .notAsked
        case .allowedAlways: return .allowed
        default: return .refused
        }
    }

    private var microphone: Access {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return .notAsked
        case .granted: return .allowed
        default: return .refused
        }
    }

    private func row(_ title: LocalizedStringKey, why: LocalizedStringKey, access: Access, ask: @escaping () -> Void) -> some View {
        LabeledContent {
            switch access {
            case .allowed:
                Text("Allowed")
            case .notAsked:
                Button("Allow", action: ask)
                    .buttonStyle(.borderedProminent)
            case .refused:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        } label: {
            Text(title)
            Text(why)
        }
        .frame(minHeight: 56)
    }
}
