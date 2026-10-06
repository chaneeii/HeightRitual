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

/// One NavigationStack around the Make / Memory TabView: screens pushed from either tab cover the
/// whole TabView, tab bar included, and popping brings it back. No tab bar hiding is needed, so it
/// cannot get stuck hidden (as it did with a stack per tab on iOS 26).
private struct MainTabs: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack(path: Binding(get: { state.navigationPath },
                                      set: { state.popped(state.navigationPath.count - $0.count) })) {
            TabView(selection: Binding(get: { state.mode ?? .memory },
                                       set: { state.handle(.mode($0)) })) {
                MemberGridView(mode: .make)
                    .tabItem { Label("Make", systemImage: "record.circle") }
                    .tag(Mode.make)
                MemberGridView(mode: .memory)
                    .tabItem { Label("Memory", systemImage: "clock.arrow.circlepath") }
                    .tag(Mode.memory)
            }
            .navigationTitle(state.mode == .make ? LocalizedStringKey("Make mode") : "Memory mode")
            .screenChrome(statusInContent: true)
            .navigationDestination(for: NavStep.self) { step in
                switch step {
                case .film: FilmView(film: state.filmState)
                case .height: HeightView(height: state.heightState)
                case .wall: MemoryWallView()
                case .record(let id): RecordDetailView(recordID: id)
                default: EmptyView()
                }
            }
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
