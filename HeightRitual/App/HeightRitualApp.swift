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
                .preferredColorScheme(colorScheme)
                .environment(\.locale, state.settings.language.locale)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}

/// With the SwiftUI lifecycle the Info.plist entry for the external display may not be used, and
/// the projector would mirror the phone (IMPLEMENTATION risk 1). Returning the configuration here
/// makes sure the projector gets its own scene with only the wall image.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = ExternalSceneDelegate.self
        }
        return configuration
    }
}
