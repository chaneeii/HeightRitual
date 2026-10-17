import SwiftUI

/// W: first start. Three welcome pages on what the app is, then the setup steps:
/// permissions, fit to wall, camera position, each with Next and Skip.
/// Every setup step can be reopened from Settings.
struct WizardView: View {
    let step: WizardStep
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if step == .welcome {
                WelcomeView()
            } else {
                setup
            }
        }
        .overlay(alignment: .topTrailing) {
            DebugWallButton()
                .padding(.trailing, 8)
        }
    }

    private var setup: some View {
        NavigationStack {
            content
                .navigationTitle(SettingsPageView.title(page))
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Setup, step \(step.rawValue) of \(WizardStep.setupSteps.count)")
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
        case .welcome, .permissions: return .permissions
        case .fitToWall: return .fitToWall
        case .cameraPosition: return .cameraPosition
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome, .permissions: PermissionsPage()
        case .fitToWall: FitToWallPage()
        case .cameraPosition: CameraPositionPage()
        }
    }
}

/// What Height Ritual is, in three pages, before any setup.
private struct WelcomeView: View {
    @Environment(AppState.self) private var state
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private let pages = [
        Page(symbol: "figure.and.child.holdinghands", title: "Height Ritual",
             text: "Families mark a child's height on a wall. Here every mark is a short film, shown life-size at the real height, and it moves with you when you move."),
        Page(symbol: "record.circle", title: "Make",
             text: "Choose who it is, stand with your heels on the line and film five seconds. Check the height and save."),
        Page(symbol: "clock.arrow.circlepath", title: "Memory",
             text: "Every record comes back on the wall at its real height. Step through them with the knob, or let them play from the first to the newest."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: item.symbol)
                            .font(.system(size: 72, weight: .light))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(.largeTitle.weight(.bold))
                        Text(item.text)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if page < pages.count - 1 {
                    BigButton(title: "Next", prominent: true) { withAnimation { page += 1 } }
                } else {
                    BigButton(title: "Set up the wall", prominent: true) { state.wizardNext() }
                }
                Button("Set up later") { state.skipWizard() }
                    .frame(minHeight: 44)
            }
            .padding()
            .readableColumn()
        }
    }
}
