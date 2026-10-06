import SwiftUI

/// Settings > Family: every member opens A1; Add opens an empty A1.
struct FamilyPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section {
                ForEach(state.store.members) { member in
                    let count = state.store.records(for: member.id).count
                    NavigationLink(value: SettingsStep.member(member.id)) {
                        LabeledContent {
                            Text(count == 1 ? L("1 record") : L("\(count) records"))
                        } label: {
                            Label {
                                Text(member.name)
                            } icon: {
                                AvatarView(member: member, size: 28)
                            }
                        }
                    }
                }
            } footer: {
                if state.store.members.isEmpty {
                    Text("Add the first family member")
                } else {
                    Text("Tap a member to rename, recolour or delete them. Deleting a member deletes their records too.")
                }
            }
            Section {
                NavigationLink(value: SettingsStep.member(nil)) {
                    Label("Add family member", systemImage: "plus")
                }
            }
        }
    }
}
