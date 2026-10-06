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
        .overlay(alignment: .bottomLeading) {
            // UI tests read the route here to check the screen and AppState agree.
            if ProcessInfo.processInfo.arguments.contains("-UITestRoute") {
                Text(verbatim: "\(state.route)")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("route-debug")
            }
        }
    }
}

/// One NavigationStack around the Make / Memory TabView: screens pushed from either tab cover the
/// whole TabView, tab bar included, and popping brings it back. No tab bar hiding is needed, so it
/// cannot get stuck hidden (as it did with a stack per tab on iOS 26).
private struct MainTabs: View {
    @Environment(AppState.self) private var state

    var body: some View {
        // Read here, in body, so Observation re-renders this view whenever they change. Values read
        // only inside a Binding's closure are not tracked: the route could move on while the stack
        // stayed put (a push lost, the tab bar left hidden), until something else redrew the view.
        let path = state.navigationPath
        let selectedTab = state.mode ?? .memory
        let showsSettings = state.showsSettings
        let showsMemberSheet = state.showsMemberSheet

        NavigationStack(path: Binding(get: { path },
                                      set: { state.popped(path.count - $0.count) })) {
            TabView(selection: Binding(get: { selectedTab },
                                       set: { state.handle(.mode($0)) })) {
                MemberGridView(mode: .make)
                    .tabItem { Label("Make", systemImage: "record.circle") }
                    .tag(Mode.make)
                MemberGridView(mode: .memory)
                    .tabItem { Label("Memory", systemImage: "clock.arrow.circlepath") }
                    .tag(Mode.memory)
            }
            // The tabs draw their own large titles (a shared title flickered when switching tabs);
            // the bar keeps only the Settings button.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .screenChrome(statusInContent: true)
            .navigationDestination(for: NavStep.self) { step in
                destination(step)
            }
        }
        .sheet(isPresented: Binding(get: { showsSettings },
                                    set: { if !$0 { state.dismissSettings() } })) {
            SettingsSheet()
        }
        .sheet(isPresented: Binding(get: { showsMemberSheet },
                                    set: { if !$0 { state.dismissMemberSheet() } })) {
            NavigationStack {
                MemberEditView(memberID: memberSheetID, inSheet: true)
            }
        }
    }

    @ViewBuilder private func destination(_ step: NavStep) -> some View {
        switch step {
        case .film: FilmView(film: state.filmState)
        case .height: HeightView(height: state.heightState)
        case .wall: MemoryWallView()
        case .record(let id): RecordDetailView(recordID: id)
        }
    }

    private var memberSheetID: UUID? {
        if case .memberEdit(let id) = state.route { return id }
        return nil
    }
}
