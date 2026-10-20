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

        return VStack(spacing: 18) {
            if let url = state.clipURL(record) {
                LoopingVideo(url: url)
                    .aspectRatio(CGFloat(state.settings.showBackground ? (record.rawAspect ?? 9.0 / 16.0)
                                                                        : (record.clipAspect ?? 9.0 / 16.0)),
                                 contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "figure.stand").font(.system(size: 44, weight: .light))
                    Text("No clip").font(Theme.label(17))
                    Text("Sample records have no clip; the wall shows a soft outline.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.hint)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Theme.ink)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.choice, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            VStack(spacing: 2) {
                Text(verbatim: HeightFormatter.text(record.heightMM, unit: unit))
                    .font(Theme.field(52).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: record.heightMM)
                Text(previous.map { HeightFormatter.difference(record.heightMM - $0.heightMM, unit: unit) }
                     ?? L("First record"))
                    .font(Theme.subtitle(18))
                    .foregroundStyle(Theme.hint)
            }

            HStack(spacing: 8) {
                step(unit == .cm ? "-1" : "-1 in") { state.stepHeight(of: record.id, by: -1, coarse: true) }
                step(unit == .cm ? "-0.5" : "-1/4") { state.stepHeight(of: record.id, by: -1, coarse: false) }
                step(unit == .cm ? "+0.5" : "+1/4") { state.stepHeight(of: record.id, by: 1, coarse: false) }
                step(unit == .cm ? "+1" : "+1 in") { state.stepHeight(of: record.id, by: 1, coarse: true) }
            }

            HStack {
                Text("Date").font(Theme.label(17)).foregroundStyle(Theme.ink)
                Spacer()
                DatePicker("Date", selection: Binding(get: { record.date },
                                                      set: { state.changeDate(of: record.id, to: $0) }),
                           in: ...Date.now, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, .english)
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(minHeight: 56)
            .background(Theme.choice, in: Capsule())

            Button { confirmDelete = true } label: {
                Text("Delete record")
                    .font(Theme.label(17))
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.choice, in: Capsule())
            }
            .buttonStyle(PressStyle())
            .confirmationDialog("Delete this record?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete record", role: .destructive) { state.deleteRecord(record.id) }
            } message: {
                Text("The clip is deleted too. This cannot be undone.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .readableColumn()
        .background(Theme.paper)
        .navigationTitle(record.date.monthYear)
        .navigationBarTitleDisplayMode(.inline)
        .screenChrome(statusInContent: true)
    }

    private func step(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(Theme.label(18).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.choice, in: Capsule())
        }
        .buttonStyle(PressStyle())
    }
}
