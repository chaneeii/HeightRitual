import SwiftUI
import UIKit

/// Drives the projector. iOS creates this scene when an HDMI adapter is connected, because
/// Info.plist registers it for the external display role. The projector then shows only the
/// wall image, while the phone keeps its own controls.
///
/// Not run on a device yet (milestone 4). See IMPLEMENTATION risk 1.
/// The projector's root view; follows the app's language like the phone.
private struct ExternalWall: View {
    @State private var state = AppState.shared
    var body: some View {
        WallView(isExternal: true)
            .environment(state)
            .environment(\.locale, state.settings.language.locale)
    }
}

final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // iOS shrinks the picture on external screens by default (overscan for old TVs), which
        // left a black band between the drawing and the floor on the projector. Use every pixel
        // of the projector's own resolution instead.
        let screen = windowScene.screen
        screen.overscanCompensation = .none
        if let native = screen.preferredMode, screen.availableModes.contains(native) {
            screen.currentMode = native
        }
        let window = UIWindow(windowScene: windowScene)
        let host = UIHostingController(rootView: ExternalWall())
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        MainActor.assumeIsolated { AppState.shared.externalDisplayConnected = true }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        MainActor.assumeIsolated { AppState.shared.externalDisplayConnected = false }
        window = nil
    }
}
