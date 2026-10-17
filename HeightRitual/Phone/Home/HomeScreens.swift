import SwiftUI

/// The phone's Home: the wheel, with the member menu laid over it when a member is chosen.
struct HomeScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        DesignCanvas(surface: .phone) {
            HomeContent(surface: .phone)
            if state.route == .memberMenu {
                MemberMenuOverlay(surface: .phone)
                    .transition(.opacity)
            } else {
                PhoneAppBar()
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: state.route == .memberMenu)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The phone's add-member screen, pushed above Home.
struct AddMemberScreen: View {
    var body: some View {
        DesignCanvas(surface: .phone) {
            AddMemberContent(surface: .phone)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }
}

/// The wall's version of the redesigned screens, inside the 608 x 1080 strip (`WallView`).
struct WallScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        DesignCanvas(surface: .wall) {
            switch state.route {
            case .addMember:
                AddMemberContent(surface: .wall)
            case .memberMenu:
                HomeContent(surface: .wall)
                MemberMenuOverlay(surface: .wall)
            case .makeHeight(let height):
                HeightContent(surface: .wall, height: height)
            case .makeSaved:
                SavedContent(surface: .wall)
            default:
                HomeContent(surface: .wall)
            }
        }
        .allowsHitTesting(false)
    }
}
