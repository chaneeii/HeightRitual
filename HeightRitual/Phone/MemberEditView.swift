import SwiftUI

/// A1: add or edit a family member. What the card shows (colour or newest photo), name, colour,
/// and Delete member for an existing one. Opened from the gear on the member menu, or in
/// Settings > Family.
/// A sheet from M1 (Cancel / Save), a pushed page in Settings > Family (Back / Save).
struct MemberEditView: View {
    let memberID: UUID?
    let inSheet: Bool
    @Environment(AppState.self) private var state
    @State private var name = ""
    @State private var colorIndex = 0
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var cardStyle: CardStyle = .photo
    @FocusState private var nameFocused: Bool

    private var existing: Member? { memberID.flatMap(state.store.member) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The newest record's photo, shown on the card when "Latest photo" is chosen.
    private var latestPhoto: UIImage? {
        existing.flatMap { state.store.latestPhotoURL(for: $0.id) }.flatMap { UIImage(contentsOfFile: $0.path) }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    cardPreview
                    Picker("Card", selection: $cardStyle) {
                        Text("Colour").tag(CardStyle.colour)
                        Text("Latest photo").tag(CardStyle.photo)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 8)
            } header: {
                Text("Card")
            } footer: {
                Text(latestPhoto == nil
                     ? "Latest photo shows the photo from the newest record. Until there is one, the card shows the colour."
                     : "Latest photo shows the photo from the newest record.")
            }
            Section("Name") {
                TextField("Name", text: $name)
                    .font(.title3)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { if canSave { save() } }
            }
            Section("Colour") {
                HStack(spacing: 0) {
                    ForEach(Palette.memberColors.indices, id: \.self) { index in
                        Button {
                            colorIndex = index
                        } label: {
                            Circle()
                                .fill(Palette.color(index))
                                .frame(width: 36, height: 36)
                                .overlay(Circle().stroke(Color.primary, lineWidth: colorIndex == index ? 3 : 0).padding(-4))
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colour \(index + 1)")
                        .accessibilityAddTraits(colorIndex == index ? .isSelected : [])
                    }
                }
            }
            if let existing {
                let count = state.store.records(for: existing.id).count
                Section {
                    Button("Delete member", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete \(existing.name)?", isPresented: $confirmDelete,
                                            titleVisibility: .visible) {
                            Button("Delete \(existing.name)", role: .destructive) {
                                state.deleteMember(existing.id)
                            }
                        } message: {
                            if count == 0 {
                                Text("This cannot be undone.")
                            } else {
                                Text("Their \(count) records and clips are deleted too. This cannot be undone.")
                            }
                        }
                }
            }
        }
        .navigationTitle(existing.map { Text(verbatim: $0.name) } ?? Text("New family member"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { state.closeMemberEdit() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing {
                name = existing.name
                colorIndex = existing.colorIndex
                cardStyle = existing.card
            } else {
                colorIndex = state.store.members.count % Palette.memberColors.count
                nameFocused = true
            }
        }
        // A colour chosen with the controller on the projector shows here too.
        .onChange(of: existing?.colorIndex) { _, new in
            if let new { colorIndex = new }
        }
        .onChange(of: existing?.name) { _, new in
            if let new { name = new }
        }
        .onChange(of: existing?.card) { _, new in
            if let new { cardStyle = new }
        }
    }

    private func save() {
        state.saveMember(id: existing?.id, name: name, colorIndex: colorIndex, cardStyle: cardStyle)
    }

    /// The card as it will look on Home.
    private var cardPreview: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8).fill(Palette.color(colorIndex))
            if cardStyle == .photo, let latestPhoto {
                Image(uiImage: latestPhoto).resizable().scaledToFill()
                    .frame(width: 60, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Rectangle().fill(Theme.paper).frame(height: 24)
                .overlay(Text(verbatim: name).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3))
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
        }
        .frame(width: 60, height: 90)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary, lineWidth: 2))
        .animation(.easeInOut(duration: 0.2), value: cardStyle)
        .animation(.easeInOut(duration: 0.2), value: colorIndex)
        .accessibilityHidden(true)
    }
}
