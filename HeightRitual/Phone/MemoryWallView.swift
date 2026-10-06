import SwiftUI

/// R2: the member's records on the wall. Manual: Previous, Replay, Next. Auto play: Stop.
/// No Record here: filming starts only in Make.
/// Every button sends the same event as the controller.
struct MemoryWallView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let records = state.currentRecords
        VStack(spacing: 12) {
            SetupBanner()

            if records.isEmpty {
                ContentUnavailableView {
                    Label("No records yet", systemImage: "figure.stand")
                } description: {
                    Text("Switch to Make to film one.")
                }
            } else {
                HStack(spacing: 8) {
                    Picker("Play", selection: autoPlayBinding) {
                        Text("Auto play").tag(true)
                        Text("Manual").tag(false)
                    }
                    .pickerStyle(.segmented)
                    // Clips as filmed, or only the person (SPEC: cut-out by default).
                    Toggle(isOn: Binding(get: { state.settings.showBackground },
                                         set: { state.setShowBackground($0) })) {
                        Label("Background", systemImage: "photo")
                    }
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Show background")
                }

                WallCopy()
                    .frame(maxHeight: .infinity)

                SelectedRecordCard()

                // Same height in both modes, so the wall copy does not jump when switching.
                Group {
                    if state.isAutoPlaying {
                        BigButton(title: "Stop", systemImage: "stop.fill", prominent: true) {
                            state.handle(.autoPlayToggle)
                        }
                    } else {
                        manualControls(count: records.count)
                    }
                }
            }
        }
        .padding()
        .readableColumn()
        .navigationTitle(state.currentMember?.name ?? L("Memory"))
        .navigationBarTitleDisplayMode(.inline)
        .screenChrome()
    }

    private var autoPlayBinding: Binding<Bool> {
        Binding(get: { state.isAutoPlaying },
                set: { if $0 != state.isAutoPlaying { state.handle(.autoPlayToggle) } })
    }

    private func manualControls(count: Int) -> some View {
        HStack(spacing: 12) {
            BigButton(title: "Previous", systemImage: "chevron.left") { state.handle(.left) }
                .disabled(state.recordIndex == 0)
            BigButton(title: "Replay", systemImage: "arrow.counterclockwise") { state.handle(.confirm) }
            BigButton(title: "Next", systemImage: "chevron.right") { state.handle(.right) }
                .disabled(state.recordIndex >= count - 1)
        }
        .labelStyle(.iconOnly)
        .accessibilityElement(children: .contain)
    }
}

/// The selected record: date, height and growth since the one before. Opens R3.
private struct SelectedRecordCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let record = state.selectedRecord {
            let unit = state.settings.unit
            let records = state.currentRecords
            let previous = state.recordIndex > 0 ? records[state.recordIndex - 1] : nil
            Button {
                state.openRecord(record.id)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.date.monthYear)
                            .font(.headline)
                        Text("\(state.recordIndex + 1) of \(records.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(HeightFormatter.text(record.heightMM, unit: unit))
                            .font(.title3.weight(.semibold).monospacedDigit())
                        Text(previous.map { HeightFormatter.difference(record.heightMM - $0.heightMM, unit: unit) }
                             ?? L("First record"))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .frame(minHeight: 56)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this record")
        }
    }
}
