import SwiftUI

/// View mode: pick a child and a year; the wall shows that year life-size.
struct BrowseView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            if state.store.children.isEmpty {
                ContentUnavailableView {
                    Label("No children yet", systemImage: "figure.and.child.holdinghands")
                } description: {
                    Text("Add a child in Settings, or load the sample family to try the wall.")
                } actions: {
                    Button("Load sample family") { state.store.loadSampleFamily() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                childSwitcher
                WallPreview()
                    .frame(height: state.externalDisplayConnected ? 150 : 230)
                recordList
                HStack(spacing: 12) {
                    Button {
                        state.handle(.record)
                    } label: {
                        Label("Record", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button {
                        state.handle(.playback)
                    } label: {
                        Label(state.screen == .playback ? "Stop" : "Play growth",
                              systemImage: state.screen == .playback ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.currentRecords.count < 2)
                }
                .controlSize(.large)
            }
        }
    }

    private var childSwitcher: some View {
        HStack {
            Button { state.moveChild(by: -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous child")
            Spacer()
            if let child = state.currentChild {
                Text(child.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.color(child.colorIndex))
            }
            Spacer()
            Button { state.moveChild(by: 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next child")
        }
        .buttonStyle(.bordered)
    }

    private var recordList: some View {
        let records = state.currentRecords
        return List {
            if records.isEmpty {
                Text("No records yet. Press Record to measure \(state.currentChild?.name ?? "").")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(records.enumerated().reversed()), id: \.element.id) { index, record in
                Button {
                    state.recordIndex = index
                } label: {
                    HStack {
                        Text(record.date.monthYear)
                        Spacer()
                        if index > 0 {
                            Text((record.heightCM - records[index - 1].heightCM).signedCM)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(record.heightCM.cmText)
                            .font(.body.monospacedDigit().weight(.medium))
                        Image(systemName: record.photoFile == nil ? "person" : "person.crop.rectangle")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                .listRowBackground(index == state.recordIndex ? Color.accentColor.opacity(0.18) : nil)
            }
            .onDelete { offsets in
                let rows = Array(records.enumerated().reversed())
                for offset in offsets { state.store.deleteRecord(rows[offset].element) }
                state.recordIndex = max(0, state.currentRecords.count - 1)
            }
        }
        .listStyle(.plain)
    }
}
