import SwiftUI

/// M1 and R1: who is it? A tile per member; Make adds a + tile at the end.
/// The knob and Left / Right move the highlight; tapping a tile opens it.
struct MemberGridView: View {
    let mode: Mode
    @Environment(AppState.self) private var state

    /// Fills the width: two columns on iPhone, more on iPad.
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 12)]

    var body: some View {
        let members = state.store.members
        Group {
            if members.isEmpty && mode == .memory {
                ContentUnavailableView {
                    Label("No family members yet", systemImage: "person.2")
                } description: {
                    Text("Add the first family member")
                } actions: {
                    Button("Add family member") { state.openMemberEdit(nil) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                ScrollView {
                    if members.isEmpty {
                        Text("Add the first family member")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            MemberTile(member: member, highlighted: highlighted(index)) {
                                state.openTile(index)
                            }
                        }
                        if mode == .make {
                            AddTile(highlighted: highlighted(members.count)) {
                                state.openTile(members.count)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    /// The controller's highlight, shown only on the screen it belongs to.
    private func highlighted(_ index: Int) -> Bool {
        state.route == (mode == .make ? .makeWho : .memoryWho) && state.highlight == index
    }
}

private struct MemberTile: View {
    let member: Member
    let highlighted: Bool
    let action: () -> Void
    @Environment(AppState.self) private var state

    var body: some View {
        let last = state.store.lastRecord(for: member.id)
        let color = Palette.color(member.colorIndex)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                AvatarView(member: member, size: 44)
                Text(member.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(last.map { HeightFormatter.text($0.heightMM, unit: state.settings.unit) }
                     ?? L("No records yet"))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(highlighted ? color : .clear, lineWidth: 3))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}

private struct AddTile: View {
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.largeTitle)
                Text("Add").font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding()
            .foregroundStyle(.tint)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(highlighted ? Color.accentColor : Color(.separator),
                        style: StrokeStyle(lineWidth: highlighted ? 3 : 1.5, dash: highlighted ? [] : [6, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a family member")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}
