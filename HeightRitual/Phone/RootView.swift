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
                .tabBarFromRoute()
                .screenChrome(statusInContent: true)
                .navigationDestination(for: NavStep.self) { step in
                    switch step {
                    case .film:
                        FilmView(film: state.filmState)
                    case .height:
                        HeightView(height: state.heightState)
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
                .tabBarFromRoute()
                .screenChrome(statusInContent: true)
                .navigationDestination(for: NavStep.self) { step in
                    switch step {
                    case .wall:
                        MemoryWallView()
                    case .record(let id):
                        RecordDetailView(recordID: id)
                    default:
                        EmptyView()
                    }
                }
        }
    }
}
