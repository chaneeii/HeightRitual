import Foundation

/// One pushed screen in a NavigationStack. The stacks are drawn from the route, so the system
/// back button and swipe stay in step with the controller.
enum NavStep: Hashable {
    case film                    // M2
    case height                  // M3
    case wall                    // R2
    case record(UUID)            // R3
    case page(SettingsPage)      // S1 to S6
    case member(UUID?)           // A1 inside Settings > Family
}

extension AppState {
    // MARK: Paths from the route

    var makePath: [NavStep] {
        switch route {
        case .makeFilm: return [.film]
        case .makeHeight: return [.film, .height]
        default: return []
        }
    }

    var memoryPath: [NavStep] {
        switch route {
        case .memoryWall: return [.wall]
        case .record(let id): return [.wall, .record(id)]
        default: return []
        }
    }

    var settingsPath: [NavStep] {
        switch route {
        case .settings(.list): return []
        case .settings(let page): return [.page(page)]
        case .memberEdit(let id) where memberEditInSettings: return [.page(.family), .member(id)]
        default: return []
        }
    }

    /// A1 opened from Settings > Family is pushed there; from M1 it is a sheet.
    var memberEditInSettings: Bool {
        if case .settings = memberEditReturn { return true }
        return false
    }

    var showsSettings: Bool {
        switch route {
        case .settings: return true
        case .memberEdit: return memberEditInSettings
        default: return false
        }
    }

    var showsMemberSheet: Bool {
        if case .memberEdit = route { return !memberEditInSettings }
        return false
    }

    /// The one stack above the tabs: Make's or Memory's screens, whichever the route is in.
    var navigationPath: [NavStep] { makePath + memoryPath }

    /// The height step's state shown on M3.
    var heightState: HeightState {
        if case .makeHeight(let height) = route { return height }
        return .editing
    }

    /// The film state shown on M2; ready while M3 is on top of it.
    var filmState: FilmState {
        if case .makeFilm(let film) = route { return film }
        return .ready
    }

    // MARK: Back from the system navigation

    /// The system back button or swipe popped `count` screens in Make or Memory.
    /// Each one is the same as Cancel / Back on the controller.
    func popped(_ count: Int) {
        for _ in 0..<max(0, count) { handle(.cancel) }
    }

    /// Settings uses NavigationLinks, so its path also grows.
    func setSettingsPath(_ path: [NavStep]) {
        let current = settingsPath
        if path.count > current.count, let last = path.last {
            switch last {
            case .page(let page): openSettingsPage(page)
            case .member(let id): openMemberEdit(id)
            default: break
            }
        } else if path.count < current.count {
            if case .memberEdit = route { closeMemberEdit() }
            if path.isEmpty, route != .settings(.list) { go(to: .settings(.list)) }
        }
    }

    /// The Settings sheet was swiped down or closed with Done.
    func dismissSettings() {
        guard showsSettings else { return }
        leaveSettings()
    }

    /// The A1 sheet was swiped down or cancelled.
    func dismissMemberSheet() {
        guard showsMemberSheet else { return }
        closeMemberEdit()
    }
}
