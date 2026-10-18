import Foundation

/// 녹음 한 건 = 폴더 하나.
///   ~/Library/Application Support/Toolbelt/Recordings/2026-10-13 14.05.22/
///     mic.m4a, system.m4a, meta.json, transcript.txt
struct Recording: Identifiable, Equatable {
    let id: String          // 폴더 이름
    let folder: URL
    let date: Date
    let meta: RecordingMeta?

    var transcriptURL: URL { folder.appendingPathComponent(RecordingStore.transcriptFile) }
    var hasTranscript: Bool { FileManager.default.fileExists(atPath: transcriptURL.path) }
    var micURL: URL { folder.appendingPathComponent(RecordingStore.micFile) }
    var systemURL: URL { folder.appendingPathComponent(RecordingStore.systemFile) }

    /// 사용자가 적은 제목. 없으면 nil (목록에는 날짜로 표시).
    var title: String? {
        guard let title = meta?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title
    }
}

struct RecordingMeta: Codable, Equatable {
    var startedAt: Date
    var duration: TimeInterval
    var micOffset: TimeInterval?
    var systemOffset: TimeInterval?
    var title: String? = nil
}

enum RecordingStore {
    static let micFile = "mic.m4a"
    static let systemFile = "system.m4a"
    static let metaFile = "meta.json"
    static let transcriptFile = "transcript.txt"

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Toolbelt/Recordings", isDirectory: true)
    }

    private static let folderFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    static func makeFolder(for date: Date) throws -> URL {
        let url = root.appendingPathComponent(folderFormat.string(from: date), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func saveMeta(_ meta: RecordingMeta, in folder: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(meta).write(to: folder.appendingPathComponent(metaFile))
    }

    /// 최신순
    static func all() -> [Recording] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders.compactMap { folder -> Recording? in
            guard let date = folderFormat.date(from: folder.lastPathComponent) else { return nil }
            let meta = (try? Data(contentsOf: folder.appendingPathComponent(metaFile)))
                .flatMap { try? decoder.decode(RecordingMeta.self, from: $0) }
            return Recording(id: folder.lastPathComponent, folder: folder, date: date, meta: meta)
        }
        .sorted { $0.date > $1.date }
    }
}
