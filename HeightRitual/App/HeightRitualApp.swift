import SwiftUI

@main
struct HeightRitualApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared

    private var colorScheme: ColorScheme? {
        switch state.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .modifier(ProjectorAccessory(state: state))
                .preferredColorScheme(colorScheme)
                .environment(\.locale, state.settings.language.locale)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}

/// Since iOS 27, an app built with the iOS 27 SDK only gets its own external display scene if it
/// registers a scene accessory; otherwise the projector mirrors the phone. Older iOS versions
/// still use the Info.plist entry and `ExternalSceneDelegate`. (Same as in TimeCapsule.)
private struct ProjectorAccessory: ViewModifier {
    let state: AppState

    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.sceneAccessory {
                ExternalNonInteractiveAccessory {
                    ExternalWall()
                        .onAppear { useFullProjectorPicture() }
                }
                .onAvailabilityChange { available in
                    state.externalDisplayConnected = available
                }
            }
        } else {
            content
        }
    }

    private func useFullProjectorPicture() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
        where scene.session.role == .windowExternalDisplayNonInteractive {
            scene.screen.useFullPicture()
        }
    }
}

/// With the SwiftUI lifecycle the Info.plist entry for the external display may not be used, and
/// the projector would mirror the phone (IMPLEMENTATION risk 1). Returning the configuration here
/// makes sure the projector gets its own scene with only the wall image. On iOS 27 the scene
/// accessory above handles the projector instead.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if #unavailable(iOS 27.0), session.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = ExternalSceneDelegate.self
        }
        return configuration
    }
}
