import SwiftUI

/// Full-width system button, large control size (CLAUDE.md: targets at least 56 pt).
/// `prominent` is the one obvious next action on a screen.
struct BigButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var prominent = false
    var role: ButtonRole?
    var tint: Color?
    let action: () -> Void

    var body: some View {
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(role: role, action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.headline)
            // With the system's regular padding this makes about 48 pt.
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .tint(tint)
    }
}

/// Settings button on every Make and Memory screen, and the status chips under the title.
/// Screens with a large title (the first screen of each tab) show the chips in their own content
/// instead (`statusInContent`): a top inset would cover the large title under iOS 26's glass bar.
struct ScreenChrome: ViewModifier {
    var statusInContent = false
    @Environment(AppState.self) private var state

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if !statusInContent {
                    StatusRow()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DebugWallButton()
                }
            }
    }
}

extension View {
    func screenChrome(statusInContent: Bool = false) -> some View {
        modifier(ScreenChrome(statusInContent: statusInContent))
    }
}

/// Projector and controller state (SPEC 5: "No projector", "Searching for controller").
/// The controller chip opens the page that fixes it.
struct StatusRow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            chip(state.externalDisplayConnected ? L("Projector") : L("No projector"),
                 systemImage: "videoprojector", active: state.externalDisplayConnected)
            Button {
                state.openControllerHelp()
            } label: {
                chip(state.controllerStatus.label, systemImage: "gamecontroller",
                     active: state.controllerStatus == .connected)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the controller settings")
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func chip(_ text: String, systemImage: String, active: Bool) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(active ? .primary : .secondary)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// "Finish setup for true size", shown on M2 and R2 until the wizard has been run.
struct SetupBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if !state.settings.wizardDone {
            Button {
                state.startWizard()
            } label: {
                HStack {
                    Label("Finish setup for true size", systemImage: "ruler")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .frame(minHeight: 56)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

/// The phone's copy of the wall: the 9:16 strip that is used on the wall.
/// The expand button shows it full screen, e.g. to check it without a projector.
struct WallCopy: View {
    @Environment(AppState.self) private var state
    @State private var expanded = false

    var body: some View {
        let strip = state.settings.wall.stripSize(for: state.wallSize)
        // Square corners: the projected strip is a rectangle, and its edge frame must stay visible.
        WallView()
            .aspectRatio(strip.width / strip.height, contentMode: .fit)
            .clipped()
            .overlay(Rectangle().stroke(Color(.separator), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                Button {
                    expanded = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(6)
                .accessibilityLabel("Show the wall full screen")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Copy of the wall")
            .fullScreenCover(isPresented: $expanded) {
                FullScreenWall()
            }
    }
}

/// The wall copy filling the phone screen: exactly the strip used on the wall, upright, with the
/// fit-to-wall values applied. Controls keep working while it is shown.
private struct FullScreenWall: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let wall = state.settings.wall
        let strip = wall.stripSize(for: state.wallSize)
        let topCM = Int(wall.visibleTopCM(imageHeight: Double(strip.height)))
        ZStack(alignment: .bottomLeading) {
            WallView()
                .aspectRatio(strip.width / strip.height, contentMode: .fit)
            Text("Projector picture: floor to \(topCM) cm")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding()
            .accessibilityLabel("Close")
        }
        .environment(state)
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}

/// Short explanatory text on setup pages.
struct Hint: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Content column for wide screens (iPad): full width on iPhone, centred and limited on iPad.
struct ReadableColumn: ViewModifier {
    var maxWidth: CGFloat = 680
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// A Form row that shows a picture on its own, without the row's card behind it.
    func bareListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }

    func readableColumn(_ maxWidth: CGFloat = 680) -> some View { modifier(ReadableColumn(maxWidth: maxWidth)) }
}
