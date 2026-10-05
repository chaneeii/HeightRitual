import SwiftUI

/// W: first-start setup. Permissions, projector placement, fit to wall, camera position,
/// each with Next and Skip. Every step can be reopened from Settings.
struct WizardView: View {
    let step: WizardStep
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(SettingsPageView.title(page))
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Setup, step \(step.rawValue + 1) of \(WizardStep.allCases.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 12) {
                        BigButton(title: "Skip") { state.wizardNext() }
                        BigButton(title: isLast ? "Finish" : "Next", prominent: true) { state.wizardNext() }
                    }
                    .padding()
                    .readableColumn()
                    .background(.bar)
                }
        }
    }

    private var isLast: Bool { step == WizardStep.allCases.last }

    private var page: SettingsPage {
        switch step {
        case .permissions: return .permissions
        case .placement: return .placement
        case .fitToWall: return .fitToWall
        case .cameraPosition: return .cameraPosition
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .permissions: PermissionsPage()
        case .placement: PlacementPage()
        case .fitToWall: FitToWallPage()
        case .cameraPosition: CameraPositionPage()
        }
    }
}
