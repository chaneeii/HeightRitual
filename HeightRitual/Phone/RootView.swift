import SwiftUI

/// Phone screen. The Make / Memory tab bar is Home (SPEC 4); each tab is a NavigationStack drawn
/// from `AppState.route`. Settings and A1 are sheets. The first-start wizard covers everything.
struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if case .wizard(let step) = state.route {
                WizardView(step: step)
            } else {
                MainTabs()
            }
        }
        .overlay(alignment: .top) {
            if let notice = state.notice {
                Text(notice)
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: state.notice)
    }
}

private struct MainTabs: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView(selection: Binding(get: { state.mode ?? .memory },
                                   set: { state.handle(.mode($0)) })) {
            MakeStack()
                .tabItem { Label("Make", systemImage: "record.circle") }
                .tag(Mode.make)
            MemoryStack()
                .tabItem { Label("Memory", systemImage: "clock.arrow.circlepath") }
                .tag(Mode.memory)
        }
        .sheet(isPresented: Binding(get: { state.showsSettings },
                                    set: { if !$0 { state.dismissSettings() } })) {
            SettingsSheet()
        }
        .sheet(isPresented: Binding(get: { state.showsMemberSheet },
                                    set: { if !$0 { state.dismissMemberSheet() } })) {
            NavigationStack {
                MemberEditView(memberID: memberSheetID, inSheet: true)
            }
        }
    }

    private var memberSheetID: UUID? {
        if case .memberEdit(let id) = state.route { return id }
        return nil
    }
}

/// M1 -> M2 -> M3.
private struct MakeStack: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack(path: Binding(get: { state.makePath },
                                      set: { state.popped(state.makePath.count - $0.count) })) {
            MemberGridView(mode: .make)
                .navigationTitle("Make mode")
                .toolbar(.visible, for: .tabBar)
                .screenChrome(subtitle: "Choose a family member and record their height")
                .navigationDestination(for: NavStep.self) { step in
                    switch step {
                    case .film:
                        FilmView(film: state.filmState)
                    case .height:
                        PlaceholderScreen(title: "Height", systemImage: "ruler",
                                          message: "The height step comes with the cut-out (milestone 6).",
                                          action: "Retake")
                    default:
                        EmptyView()
                    }
                }
        }
    }
}

/// R1 -> R2 -> R3.
private struct MemoryStack: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack(path: Binding(get: { state.memoryPath },
                                      set: { state.popped(state.memoryPath.count - $0.count) })) {
            MemberGridView(mode: .memory)
                .navigationTitle("Memory mode")
                .toolbar(.visible, for: .tabBar)
                .screenChrome(subtitle: "Choose a family member to see how they have grown")
                .navigationDestination(for: NavStep.self) { step in
                    switch step {
                    case .wall:
                        MemoryWallView()
                    case .record:
                        PlaceholderScreen(title: "Record", systemImage: "person.crop.rectangle",
                                          message: "Changing or deleting one record comes with clip playback (milestone 7).",
                                          action: nil)
                    default:
                        EmptyView()
                    }
                }
        }
    }
}

/// Stand-in until the screen is built. The action sends Cancel / Back, as the controller would.
private struct PlaceholderScreen: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey
    let action: LocalizedStringKey?
    @Environment(AppState.self) private var state

    var body: some View {
        ContentUnavailableView {
            Label("Not built yet", systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let action {
                Button(action) { state.handle(.cancel) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .screenChrome()
    }
}
