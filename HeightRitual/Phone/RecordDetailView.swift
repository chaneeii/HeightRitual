import SwiftUI

/// R3: one record. Its clip, date, height and growth since the record before;
/// the height can be corrected and the record deleted (SPEC 12, R4).
struct RecordDetailView: View {
    let recordID: UUID
    @Environment(AppState.self) private var state
    @State private var confirmDelete = false

    var body: some View {
        if let record = state.store.record(recordID) {
            content(record)
        } else {
            ContentUnavailableView("No records yet", systemImage: "figure.stand")
        }
    }

    private func content(_ record: GrowthRecord) -> some View {
        let unit = state.settings.unit
        let records = state.store.records(for: record.memberID)
        let index = records.firstIndex { $0.id == record.id } ?? 0
        let previous = index > 0 ? records[index - 1] : nil

        return VStack(spacing: 16) {
            if let url = state.clipURL(record) {
                LoopingVideo(url: url)
                    .aspectRatio(CGFloat(state.settings.showBackground ? (record.rawAspect ?? 9.0 / 16.0)
                                                                        : (record.clipAspect ?? 9.0 / 16.0)),
                                 contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No clip", systemImage: "figure.stand")
                } description: {
                    Text("Sample records have no clip; the wall shows a soft outline.")
                }
            }

            VStack(spacing: 4) {
                Text(verbatim: HeightFormatter.text(record.heightMM, unit: unit))
                    .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: record.heightMM)
                Text(previous.map { HeightFormatter.difference(record.heightMM - $0.heightMM, unit: unit) }
                     ?? L("First record"))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                step(unit == .cm ? "-1" : "-1 in") { state.stepHeight(of: record.id, by: -1, coarse: true) }
                step(unit == .cm ? "-0.5" : "-1/4") { state.stepHeight(of: record.id, by: -1, coarse: false) }
                step(unit == .cm ? "+0.5" : "+1/4") { state.stepHeight(of: record.id, by: 1, coarse: false) }
                step(unit == .cm ? "+1" : "+1 in") { state.stepHeight(of: record.id, by: 1, coarse: true) }
            }

            BigButton(title: "Delete record", role: .destructive, tint: .red) { confirmDelete = true }
                .confirmationDialog("Delete this record?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete record", role: .destructive) { state.deleteRecord(record.id) }
                } message: {
                    Text("The clip is deleted too. This cannot be undone.")
                }
        }
        .padding()
        .readableColumn()
        .navigationTitle(record.date.monthYear)
        .navigationBarTitleDisplayMode(.inline)
        .tabBarFromRoute()
        .screenChrome()
    }

    private func step(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(.headline.monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
    }
}
