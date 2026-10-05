import SwiftUI

@main
struct HeightRitualApp: App {
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
