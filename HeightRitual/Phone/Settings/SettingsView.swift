import SwiftUI

/// S as a sheet: a NavigationStack drawn from the route. Back on a page goes to the list;
/// Done (or swiping the sheet down) returns to where Settings was opened from.
struct SettingsSheet: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let path = state.settingsPath    // read in body: tracked by Observation
        NavigationStack(path: Binding(get: { path }, set: { state.setSettingsPath($0) })) {
            SettingsList()
                .navigationTitle("Settings")
                .toolbarBackground(SettingsStyle.background, for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        DebugWallButton(color: .white)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { state.dismissSettings() }
                    }
                }
                .navigationDestination(for: SettingsStep.self) { step in
                    switch step {
                    case .page(let page):
                        SettingsPageView(page: page)
                    case .member(let id):
                        MemberEditView(memberID: id, inSheet: false)
                    }
                }
        }
        .overlay {
            #if DEBUG
            // The sheet covers the root view's preview, so it shows its own.
            if state.debugShowsWall { DebugWallPreview() }
            #endif
        }
    }
}

/// One settings page; also used by the wizard.
struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        content
            .navigationTitle(Self.title(page))
            .navigationBarTitleDisplayMode(.inline)
    }

    static func title(_ page: SettingsPage) -> LocalizedStringKey {
        switch page {
        case .list: return "Settings"
        case .family: return "Family"
        case .setupGuide: return "Setup guide"
        case .fitToWall: return "Fit to wall"
        case .cameraPosition: return "Camera position"
        case .units: return "Units"
        case .pointColour: return "Point colour"
        case .sound: return "Sound"
        case .confirmSample: return "Sample family"
        case .confirmDelete: return "Delete everything"
        case .controller: return "Controller"
        case .permissions: return "Permissions"
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .list: SettingsList()
        case .family: FamilyPage()
        case .setupGuide: SetupGuidePage()
        case .fitToWall: FitToWallPage()
        case .cameraPosition: CameraPositionPage()
        case .units: UnitsPage()
        case .pointColour: PointColourPage()
        case .sound: SoundPage()
        case .confirmSample, .confirmDelete: SettingsQuestionPage()
        case .controller: ControllerPage()
        case .permissions: PermissionsPage()
        }
    }
}

/// The settings list's white and light blue look, also used by the projector's settings tiles.
/// The same in light and dark appearance, so the list is always drawn with light-appearance
/// (dark) text and controls.
enum SettingsStyle {
    static let background = Color(red: 0.91, green: 0.95, blue: 1.00)   // light blue
    static let row = Color(red: 1.00, green: 1.00, blue: 1.00)          // white
    static let icon = Color(red: 0.20, green: 0.48, blue: 0.85)         // clear blue
    /// The controller's choice outline: the point colour (`Theme.pointColour`). Black (the default)
    /// is drawn white on the projector, where the settings pages are black.
    static func selection(_ accentIndex: Int?, onWall: Bool) -> Color {
        Theme.pointColour(accentIndex, onDark: onWall)
    }
}

private struct SettingsList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.settings
        Form {
            Section {
                link(.family, "Family", detail: "Add, rename or remove the people you measure",
                     systemImage: "person.2", value: "\(state.store.members.count)")
            }
            .listRowBackground(SettingsStyle.row)
            Section {
                link(.setupGuide, "Setup guide", detail: "Where to put the projector and the phone",
                     systemImage: "book")
                link(.fitToWall, "Fit to wall", detail: "Make projected centimetres match a tape measure",
                     systemImage: "ruler")
                link(.cameraPosition, "Camera position", detail: "Where the floor and 100 cm are in the camera picture",
                     systemImage: "camera.viewfinder",
                     value: settings.camera == nil ? L("Not set") : L("Set"))
            } header: {
                Text("Setup")
            } footer: {
                Text("The first time, do these in order: fit to wall, then camera position. Without them heights on the wall are not true size.")
            }
            .listRowBackground(SettingsStyle.row)
            Section {
                // A page of its own, so the projector shows its Units page too (route .settings(.units)).
                link(.units, "Units", detail: "For every height on the phone and the wall",
                     systemImage: "textformat.123",
                     value: settings.unit == .cm ? L("Centimetres") : L("Feet and inches"))
                link(.pointColour, "Point colour", detail: "Borders, buttons and the dial, on the phone and the wall",
                     systemImage: "paintpalette",
                     value: settings.accentIndex.map { "Colour \($0 + 1)" } ?? "Black")
                link(.sound, "Sound", detail: "Record and play sound with each clip",
                     systemImage: "speaker.wave.2", value: settings.soundOn ? "On" : "Off")
                link(.controller, "Controller", detail: "Connection, and a test of every button",
                     systemImage: "gamecontroller", value: controllerText)
                link(.permissions, "Permissions", detail: "Camera, Bluetooth and microphone",
                     systemImage: "hand.raised")
            }
            .listRowBackground(SettingsStyle.row)
            Section {
                Button {
                    state.startTutorial()
                } label: {
                    Label {
                        Text("Onboarding with controller")
                        Text("Demo: a guided first use to learn the controller")
                    } icon: {
                        Image(systemName: "gamecontroller")
                    }
                }
                // Both ask first on a page of their own, so the projector asks the same question.
                Button {
                    state.openSettingsPage(.confirmSample)
                } label: {
                    Label {
                        Text("Load sample family")
                        Text("Nora and Leo, to try Memory without filming")
                    } icon: {
                        Image(systemName: "person.3")
                    }
                }
                Button(role: .destructive) {
                    state.openSettingsPage(.confirmDelete)
                } label: {
                    Label("Delete everything", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Delete everything removes members, records and clips. Setup values are kept.")
            }
            .listRowBackground(SettingsStyle.row)
        }
        .scrollContentBackground(.hidden)
        .background(SettingsStyle.background)
        .tint(SettingsStyle.icon)
        .environment(\.colorScheme, .light)
    }

    /// A row with its title, one line on what it is for, and the current value.
    private func link(_ page: SettingsPage, _ title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String,
                      value: String? = nil) -> some View {
        NavigationLink(value: SettingsStep.page(page)) {
            LabeledContent {
                if let value { Text(value) }
            } label: {
                Label {
                    Text(title)
                    Text(detail)
                } icon: {
                    Image(systemName: systemImage)
                }
            }
        }
    }

    private var controllerText: String {
        switch state.controllerStatus {
        case .connected: return L("Connected")
        case .searching, .connecting: return L("Searching")
        case .notAllowed: return L("Not allowed")
        case .bluetoothOff: return L("Bluetooth off")
        }
    }
}
