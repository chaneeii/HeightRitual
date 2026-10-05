import UIKit
import Observation

/// Children and measurements, stored on this phone only:
/// Documents/records.json plus one PNG cut-out per record in Documents/photos.
@MainActor
@Observable
final class RecordStore {
    private(set) var children: [Child] = []
    private(set) var records: [GrowthRecord] = []

    @ObservationIgnored private var imageCache: [String: UIImage] = [:]

    private struct Snapshot: Codable {
        var children: [Child]
        var records: [GrowthRecord]
    }

    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var dataURL: URL { docs.appendingPathComponent("records.json") }
    private var photosDir: URL { docs.appendingPathComponent("photos", isDirectory: true) }

    init() { load() }

    // MARK: Queries

    func records(for childID: UUID) -> [GrowthRecord] {
        records.filter { $0.childID == childID }.sorted { $0.date < $1.date }
    }

    func image(for record: GrowthRecord) -> UIImage? {
        guard let file = record.photoFile else { return nil }
        if let cached = imageCache[file] { return cached }
        let image = UIImage(contentsOfFile: photosDir.appendingPathComponent(file).path)
        imageCache[file] = image
        return image
    }

    // MARK: Changes

    func addChild(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        children.append(Child(name: trimmed, colorIndex: children.count))
        save()
    }

    func deleteChild(_ child: Child) {
        for record in records where record.childID == child.id { removePhoto(of: record) }
        records.removeAll { $0.childID == child.id }
        children.removeAll { $0.id == child.id }
        save()
    }

    @discardableResult
    func addRecord(childID: UUID, heightMM: Int, date: Date = .now, cutout: UIImage?) -> GrowthRecord {
        var file: String?
        if let cutout, let data = cutout.pngData() {
            let name = UUID().uuidString + ".png"
            try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
            if (try? data.write(to: photosDir.appendingPathComponent(name))) != nil {
                file = name
                imageCache[name] = cutout
            }
        }
        let record = GrowthRecord(childID: childID, date: date, heightMM: heightMM, photoFile: file)
        records.append(record)
        save()
        return record
    }

    func deleteRecord(_ record: GrowthRecord) {
        removePhoto(of: record)
        records.removeAll { $0.id == record.id }
        save()
    }

    /// Removes every child, record and photo. Use after each test session.
    func deleteAll() {
        try? FileManager.default.removeItem(at: photosDir)
        imageCache.removeAll()
        children = []
        records = []
        save()
    }

    /// Replaces everything with a sample family so the view mode can be shown right away.
    func loadSampleFamily() {
        deleteAll()
        let nora = Child(name: "Nora", colorIndex: 0)
        let leo = Child(name: "Leo", colorIndex: 1)
        children = [nora, leo]
        let calendar = Calendar(identifier: .gregorian)
        func date(_ year: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: 8, day: 15)) ?? .now
        }
        let noraHeights = [870, 950, 1030, 1100, 1160, 1210]
        for (i, mm) in noraHeights.enumerated() {
            records.append(GrowthRecord(childID: nora.id, date: date(2020 + i), heightMM: mm))
        }
        let leoHeights = [760, 840, 920, 990]
        for (i, mm) in leoHeights.enumerated() {
            records.append(GrowthRecord(childID: leo.id, date: date(2022 + i), heightMM: mm))
        }
        save()
    }

    // MARK: Persistence

    private func removePhoto(of record: GrowthRecord) {
        guard let file = record.photoFile else { return }
        try? FileManager.default.removeItem(at: photosDir.appendingPathComponent(file))
        imageCache[file] = nil
    }

    private func load() {
        guard let data = try? Data(contentsOf: dataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? decoder.decode(Snapshot.self, from: data) {
            children = snapshot.children
            records = snapshot.records
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Snapshot(children: children, records: records)) {
            try? data.write(to: dataURL, options: .atomic)
        }
    }
}
