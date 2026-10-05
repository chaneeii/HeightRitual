import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var confirmDeleteAll = false
    @State private var confirmSample = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Children") {
                    ForEach(state.store.children) { child in
                        HStack {
                            Circle().fill(Palette.color(child.colorIndex)).frame(width: 12, height: 12)
                            Text(child.name)
                            Spacer()
                            Text("\(state.store.records(for: child.id).count) records")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        let children = state.store.children
                        for offset in offsets { state.store.deleteChild(children[offset]) }
                        state.childIndex = 0
                        state.recordIndex = max(0, state.currentRecords.count - 1)
                    }
                    HStack {
                        TextField("Name", text: $newName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(addChild)
                        Button("Add", action: addChild)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Wall") {
                    Button("Calibrate the projection") {
                        dismiss()
                        state.startCalibration()
                    }
                    LabeledContent("Projector", value: state.externalDisplayConnected ? "Connected" : "Not connected")
                    LabeledContent("Visible height", value: "\(Int(state.calibration.visibleTopCM(for: state.wallSize))) cm")
                }

                Section {
                    LabeledContent("Status", value: state.controllerStatus.label)
                    Button("Forget this controller") { state.controller.forgetController() }
                } header: {
                    Text("Controller")
                } footer: {
                    Text("Use Forget when a new controller board replaces the old one.")
                }

                Section {
                    Button("Load sample family") { confirmSample = true }
                    Button("Delete all records and photos", role: .destructive) { confirmDeleteAll = true }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Photos stay on this phone only. Delete everything after each test session.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete every child, record and photo on this phone?",
                                isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    state.store.deleteAll()
                    state.childIndex = 0
                    state.recordIndex = 0
                }
            }
            .confirmationDialog("Replace all data with the sample family?",
                                isPresented: $confirmSample, titleVisibility: .visible) {
                Button("Replace with sample family", role: .destructive) {
                    state.store.loadSampleFamily()
                    state.childIndex = 0
                    state.recordIndex = max(0, state.currentRecords.count - 1)
                }
            }
        }
    }

    private func addChild() {
        state.store.addChild(name: newName)
        newName = ""
    }
}
