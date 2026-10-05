import PhotosUI
import SwiftUI

/// A1: add or edit a family member. Photo, name, colour, and Delete member for an existing one.
/// A sheet from M1 (Cancel / Save), a pushed page in Settings > Family (Back / Save).
struct MemberEditView: View {
    let memberID: UUID?
    let inSheet: Bool
    @Environment(AppState.self) private var state
    @State private var name = ""
    @State private var colorIndex = 0
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var photoChange: PhotoChange = .keep
    @FocusState private var nameFocused: Bool

    private var existing: Member? { memberID.flatMap(state.store.member) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The member as it will look after Save, for the avatar preview.
    private var preview: Member {
        Member(id: existing?.id ?? UUID(), name: name, colorIndex: colorIndex, photoFile: existing?.photoFile)
    }

    private var hasPhoto: Bool {
        switch photoChange {
        case .set: return true
        case .remove: return false
        case .keep: return existing?.photoFile != nil
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    AvatarView(member: preview, size: 88, pendingPhoto: pendingImage,
                               showsPhoto: photoChange != .remove)
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Text(hasPhoto ? "Change photo" : "Choose photo")
                        }
                        if hasPhoto {
                            Button("Remove photo", role: .destructive) {
                                photoChange = .remove
                                pendingImage = nil
                                pickerItem = nil
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Photo")
            } footer: {
                Text("Without a photo, the first letter of the name is shown in the chosen colour.")
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
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = image.profileJPEG() else { return }
                pendingImage = UIImage(data: jpeg)
                photoChange = .set(jpeg)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing {
                name = existing.name
                colorIndex = existing.colorIndex
            } else {
                colorIndex = state.store.members.count % Palette.memberColors.count
                nameFocused = true
            }
        }
    }

    private func save() {
        state.saveMember(id: existing?.id, name: name, colorIndex: colorIndex, photo: photoChange)
    }
}
