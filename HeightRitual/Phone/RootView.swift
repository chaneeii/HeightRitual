import SwiftUI

/// Phone screen. Home is the wheel of members; one NavigationStack drawn from `AppState.route`
/// pushes adding a member, Record and Lookback above it. Settings and A1 are sheets. The
/// first-start wizard covers everything. Debug builds can show the wall picture instead.
struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if case .wizard(let step) = state.route {
                WizardView(step: step)
            } else {
                MainStack()
            }
        }
        .overlay {
            #if DEBUG
            if state.debugShowsWall { DebugWallPreview() }
            #endif
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

/// One NavigationStack above Home. Pushed screens cover Home completely and popping brings it back.
private struct MainStack: View {
    @Environment(AppState.self) private var state

    var body: some View {
        // Read here, in body, so Observation re-renders this view whenever they change. Values read
        // only inside a Binding's closure are not tracked: the route could move on while the stack
        // stayed put, until something else redrew the view.
        let path = state.navigationPath
        let showsSettings = state.showsSettings
        let showsMemberSheet = state.showsMemberSheet

        NavigationStack(path: Binding(get: { path },
                                      set: { state.popped(path.count - $0.count) })) {
            HomeScreen()
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
        case .addMember: AddMemberScreen()
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

#if DEBUG
/// Debug builds: the wall picture on the phone, with the controller's buttons underneath so the
/// wall's screens can be driven without the box.
struct DebugWallPreview: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "Wall preview")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                DebugWallButton(color: .white)
            }
            .padding(.horizontal, 12)

            WallView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 18) {
                pad(.back, "Back") { state.handle(.cancel) }
                pad(.left, "Left") { state.handle(.left) }
                pad(.confirm, "Confirm") { state.handle(.confirm) }
                pad(.right, "Right") { state.handle(.right) }
                Button { state.handle(.record) } label: {
                    Image(systemName: "record.circle").font(.system(size: 34)).foregroundStyle(.red)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.vertical, 10)
        }
        .padding(.top, 50)
        .padding(.bottom, 20)
        .background(Color.black)
        .ignoresSafeArea()
    }

    private func pad(_ glyph: ControlIcon.Glyph, _ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ControlIcon(glyph: glyph, size: 44).foregroundStyle(.white)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(Text(verbatim: "Debug pad \(name)"))
    }
}
#endif
