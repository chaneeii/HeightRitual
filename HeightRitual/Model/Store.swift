import Foundation
import Observation

/// Members and records, stored on this phone only:
/// Documents/records.json plus Documents/media/<uuid>.mov and <uuid>.png per record.
@MainActor
@Observable
final class Store {
    private(set) var members: [Member] = []
    private(set) var records: [GrowthRecord] = []

    private struct Snapshot: Codable {
        var members: [Member]
        var records: [GrowthRecord]
    }

    @ObservationIgnored let directory: URL
    private var dataURL: URL { directory.appendingPathComponent("records.json") }
    var mediaDirectory: URL { directory.appendingPathComponent("media", isDirectory: true) }

    /// `directory` is the Documents folder in the app; tests pass a temporary folder.
    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        self.directory = directory
        if FileManager.default.fileExists(atPath: dataURL.path) {
            load()
        } else {
            // 첫 실행: 샘플 가족으로 Memory를 바로 보여줄 수 있게
            loadSampleFamily()
        }
    }

    // MARK: Queries

    func member(_ id: UUID) -> Member? { members.first { $0.id == id } }

    func record(_ id: UUID) -> GrowthRecord? { records.first { $0.id == id } }

    /// Oldest first.
    func records(for memberID: UUID) -> [GrowthRecord] {
        records.filter { $0.memberID == memberID }.sorted { $0.date < $1.date }
    }

    func lastRecord(for memberID: UUID) -> GrowthRecord? { records(for: memberID).last }

    func mediaURL(_ file: String?) -> URL? {
        file.map { mediaDirectory.appendingPathComponent($0) }
    }

    // MARK: Members

    @discardableResult
    func addMember(name: String, colorIndex: Int? = nil) -> Member? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let member = Member(name: trimmed, colorIndex: colorIndex ?? members.count)
        members.append(member)
        save()
        return member
    }

    func updateMember(_ member: Member) {
        guard let index = members.firstIndex(where: { $0.id == member.id }) else { return }
        let trimmed = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        members[index] = Member(id: member.id, name: trimmed, colorIndex: member.colorIndex,
                                photoFile: members[index].photoFile)
        save()
    }

    /// Saves (JPEG data) or removes a member's profile photo.
    func setPhoto(_ change: PhotoChange, for id: UUID) {
        guard let index = members.firstIndex(where: { $0.id == id }) else { return }
        if let old = members[index].photoFile {
            try? FileManager.default.removeItem(at: mediaDirectory.appendingPathComponent(old))
            members[index].photoFile = nil
        }
        if case .set(let data) = change {
            // A new name each time, so views showing the old file reload.
            let name = "\(id.uuidString)-photo-\(UUID().uuidString.prefix(8)).jpg"
            try? FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            if (try? data.write(to: mediaDirectory.appendingPathComponent(name), options: .atomic)) != nil {
                members[index].photoFile = name
            }
        }
        save()
    }

    func deleteMember(_ id: UUID) {
        if let photo = member(id)?.photoFile {
            try? FileManager.default.removeItem(at: mediaDirectory.appendingPathComponent(photo))
        }
        for record in records where record.memberID == id { removeMedia(of: record) }
        records.removeAll { $0.memberID == id }
        members.removeAll { $0.id == id }
        save()
    }

    // MARK: Records

    /// Moves the clip and poster (if any) into the media folder and saves the record.
    @discardableResult
    func addRecord(memberID: UUID, heightMM: Int, source: GrowthRecord.HeightSource,
                   clip: ProcessedClip?, date: Date = .now) -> GrowthRecord {
        var record = GrowthRecord(memberID: memberID, date: date, heightMM: heightMM, heightSource: source)
        if let clip {
            try? FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            record.videoFile = moveIntoMedia(clip.videoURL, name: "\(record.id.uuidString).mov")
            record.posterFile = moveIntoMedia(clip.posterURL, name: "\(record.id.uuidString).png")
            record.hasSound = clip.hasSound
            record.bodyRatio = clip.bodyRatio
            record.floorRatio = clip.floorRatio
            record.rawVideoFile = moveIntoMedia(clip.rawVideoURL, name: "\(record.id.uuidString)-raw.mov")
            record.rawBodyRatio = clip.rawBodyRatio
            record.rawFloorRatio = clip.rawFloorRatio
            record.clipAspect = clip.clipAspect
            record.rawAspect = clip.rawAspect
            record.duration = clip.duration
        }
        records.append(record)
        save()
        return record
    }

    func updateHeight(of id: UUID, heightMM: Int) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].heightMM = heightMM
        records[index].heightSource = .edited
        save()
    }

    func deleteRecord(_ id: UUID) {
        guard let record = record(id) else { return }
        removeMedia(of: record)
        records.removeAll { $0.id == id }
        save()
    }

    /// Removes every member, record and media file. Setup values live in SettingsStore and stay.
    func deleteAll() {
        try? FileManager.default.removeItem(at: mediaDirectory)
        members = []
        records = []
        save()
    }

    /// Replaces everything with Nora (six records) and Leo (four), without clips.
    func loadSampleFamily() {
        deleteAll()
        let nora = Member(name: "Nora", colorIndex: 0)
        let leo = Member(name: "Leo", colorIndex: 1)
        members = [nora, leo]
        let calendar = Calendar(identifier: .gregorian)
        func date(_ year: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: 8, day: 15)) ?? .now
        }
        for (i, mm) in [870, 950, 1030, 1100, 1160, 1210].enumerated() {
            records.append(GrowthRecord(memberID: nora.id, date: date(2020 + i), heightMM: mm, heightSource: .sample))
        }
        for (i, mm) in [760, 840, 920, 990].enumerated() {
            records.append(GrowthRecord(memberID: leo.id, date: date(2022 + i), heightMM: mm, heightSource: .sample))
        }
        save()
    }

    // MARK: Persistence

    private func moveIntoMedia(_ source: URL?, name: String) -> String? {
        guard let source else { return nil }
        let target = mediaDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.moveItem(at: source, to: target)
            return name
        } catch {
            return nil
        }
    }

    private func removeMedia(of record: GrowthRecord) {
        for file in [record.videoFile, record.posterFile, record.rawVideoFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: mediaDirectory.appendingPathComponent(file))
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: dataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? decoder.decode(Snapshot.self, from: data) {
            members = snapshot.members
            records = snapshot.records
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? encoder.encode(Snapshot(members: members, records: records)) {
            try? data.write(to: dataURL, options: .atomic)
        }
    }
}
