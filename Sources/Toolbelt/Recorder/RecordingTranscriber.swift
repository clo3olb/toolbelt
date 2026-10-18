import AVFoundation
import Speech

/// Apple 기기 내 음성 인식(SpeechAnalyzer, macOS 26)으로 녹음을 전사한다.
/// 마이크("나")와 컴퓨터 소리("상대")를 따로 전사한 뒤
///   transcript.txt        — 시간순으로 합친 사람이 읽는 전사
///   transcript-apple.json — 결과·단어 단위 시간과 신뢰도 원본 (다른 엔진과 비교·문장 재분할용)
/// 을 저장한다. 다른 엔진을 붙이면 transcript-<엔진>.json으로 나란히 둔다.
enum RecordingTranscriber {
    static let locale = Locale(identifier: "ko-KR")

    @discardableResult
    static func transcribe(_ recording: Recording) async throws -> URL {
        let sources: [(name: String, url: URL, speaker: String, offset: TimeInterval?)] = [
            ("mic", recording.micURL, "나", recording.meta?.micOffset),
            ("system", recording.systemURL, "상대", recording.meta?.systemOffset),
        ]
        var tracks: [TranscriptTrack] = []
        for source in sources where FileManager.default.fileExists(atPath: source.url.path) {
            let offset = source.offset ?? 0
            let segments = try await transcribeFile(source.url, offset: offset)
            tracks.append(TranscriptTrack(track: source.name, file: source.url.lastPathComponent,
                                          speaker: source.speaker, offset: offset, segments: segments))
        }

        let transcript = Transcript(engine: "apple-speechtranscriber", locale: locale.identifier,
                                    createdAt: Date(), tracks: tracks)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(transcript).write(to: recording.folder.appendingPathComponent("transcript-apple.json"))

        let lines = tracks
            .flatMap { track in track.segments.map { (start: $0.start, speaker: track.speaker, text: $0.text) } }
            .sorted { $0.start < $1.start }
            .map { "[\(timestamp($0.start))] \($0.speaker): \($0.text)" }
        let body = lines.isEmpty ? "(인식된 말이 없습니다)" : lines.joined(separator: "\n")
        try (body + "\n").write(to: recording.transcriptURL, atomically: true, encoding: .utf8)
        return recording.transcriptURL
    }

    /// 시간은 모두 녹음 시작 기준(트랙 offset 반영) 초.
    private static func transcribeFile(_ url: URL, offset: TimeInterval) async throws -> [TranscriptSegment] {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        // 한국어 모델이 없으면 내려받는다 (처음 한 번)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let file = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () -> [TranscriptSegment] in
            var out: [TranscriptSegment] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let words = result.text.runs.compactMap { run -> TranscriptWord? in
                    let word = String(result.text[run.range].characters).trimmingCharacters(in: .whitespaces)
                    guard !word.isEmpty, let range = run.audioTimeRange else { return nil }
                    return TranscriptWord(start: range.start.seconds + offset, end: range.end.seconds + offset,
                                          text: word, confidence: run.transcriptionConfidence)
                }
                out.append(TranscriptSegment(start: result.range.start.seconds + offset,
                                             end: result.range.end.seconds + offset,
                                             text: text, words: words))
            }
            return out
        }
        if let end = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - transcript-<엔진>.json 형식

struct Transcript: Codable {
    var engine: String
    var locale: String
    var createdAt: Date
    var tracks: [TranscriptTrack]
}

struct TranscriptTrack: Codable {
    var track: String      // "mic" | "system"
    var file: String       // mic.m4a | system.m4a
    var speaker: String    // "나" | "상대"
    /// 이 트랙 파일의 0초가 녹음 시작 기준 몇 초인지
    var offset: TimeInterval
    var segments: [TranscriptSegment]
}

struct TranscriptSegment: Codable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var words: [TranscriptWord]
}

struct TranscriptWord: Codable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var confidence: Double?
}
