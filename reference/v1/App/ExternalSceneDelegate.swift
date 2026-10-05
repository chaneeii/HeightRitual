import SwiftUI
import UIKit

/// Drives the projector. iOS creates this scene when an HDMI adapter is connected,
/// because Info.plist registers it for the external display role. The projector then
/// shows only the wall image, while the phone keeps its own controls.
final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let host = UIHostingController(rootView: WallView(isExternal: true).environment(AppState.shared))
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        AppState.shared.externalDisplayConnected = true
        AppState.shared.wallSize = windowScene.screen.bounds.size
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        AppState.shared.externalDisplayConnected = false
        window = nil
    }
}
