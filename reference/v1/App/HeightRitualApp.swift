import SwiftUI

@main
struct HeightRitualApp: App {
    @State private var state = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .preferredColorScheme(.dark)
        }
    }
}
