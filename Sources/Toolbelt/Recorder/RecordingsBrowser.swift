import AppKit
import SwiftUI

/// 메인 창의 "녹음" 페이지: 왼쪽 녹음 목록, 오른쪽 재생 + 전사 내역.
@MainActor
final class RecordingsBrowserState: ObservableObject {
    @Published var selectedID: String?
    let player = RecordingPlayer()
}

struct RecordingsBrowser: View {
    @ObservedObject var controller: RecordingController
    @ObservedObject var state: RecordingsBrowserState

    private var selected: Recording? {
        controller.recordings.first { $0.id == state.selectedID }
    }

    var body: some View {
        HSplitView {
            List(selection: $state.selectedID) {
                ForEach(controller.recordings) { recording in
                    RecordingListRow(recording: recording,
                                     isCurrent: controller.currentRecordingID == recording.id,
                                     transcription: controller.transcriptionState(of: recording.id))
                        .tag(recording.id)
                }
            }
            .safeAreaInset(edge: .top) { RecordBar(controller: controller) }
            .overlay {
                if controller.recordings.isEmpty {
                    Text("녹음이 없습니다").foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

            Group {
                if let selected {
                    RecordingDetailView(recording: selected, controller: controller, player: state.player)
                        .id(selected.id)
                } else {
                    Text("녹음을 선택하세요").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 420)
        }
        .onChange(of: state.selectedID) { _, _ in state.player.load(selected) }
        // 녹음을 시작하면 그 녹음을 선택해 제목을 바로 적을 수 있게 한다
        .onChange(of: controller.currentRecordingID) { _, id in if let id { state.selectedID = id } }
        .onAppear {
            if state.selectedID == nil { state.selectedID = controller.recordings.first?.id }
            state.player.load(selected)
        }
    }
}

/// 목록 위 녹음 막대: 녹음 시작/정지, 경과 시간, 통화 자동 녹음
private struct RecordBar: View {
    @ObservedObject var controller: RecordingController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: controller.toggle) {
                    ZStack {
                        Circle().fill(controller.isRecording ? Color.red.opacity(0.15) : Color.red)
                        if controller.isRecording {
                            RoundedRectangle(cornerRadius: 3).fill(Color.red).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "mic.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(controller.isStarting)
                .help(controller.isRecording ? "녹음 정지" : "녹음 시작")

                VStack(alignment: .leading, spacing: 1) {
                    Text(controller.isRecording ? "녹음 중  \(RecordingFormat.duration(controller.elapsed))"
                         : controller.isStarting ? "녹음 준비 중…" : "녹음 시작")
                        .font(.callout.weight(.semibold)).monospacedDigit()
                    if let name = controller.autoCallName {
                        Text(controller.autoCallEnding ? "\(name) 통화 종료 — 곧 정지" : "\(name) 통화 자동 녹음")
                            .font(.caption).foregroundStyle(.red).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            Toggle(isOn: Binding(get: { controller.autoRecordCalls }, set: controller.setAutoRecordCalls)) {
                Text("통화 자동 녹음").font(.caption)
            }
            .toggleStyle(.switch).controlSize(.mini)
            if let message = controller.errorMessage {
                Text(message).font(.caption2).foregroundStyle(.orange).lineLimit(3)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }
}

private struct RecordingListRow: View {
    let recording: Recording
    let isCurrent: Bool
    let transcription: RecordingController.TranscriptionState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isCurrent ? "record.circle.fill" : recording.hasTranscript ? "text.bubble.fill" : "waveform")
                .foregroundStyle(isCurrent ? Color.red : recording.hasTranscript ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title ?? RecordingFormat.day.string(from: recording.date))
                    .font(.body).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let length = recording.meta.map { RecordingFormat.duration($0.duration) } ?? "정보 없음"
        let status: String
        switch transcription {
        case _ where isCurrent: status = "녹음 중…"
        case .running: status = "\(length) · 전사 중…"
        case .queued: status = "\(length) · 전사 대기"
        case .failed: status = "\(length) · 전사 실패"
        case .none: status = length
        }
        // 제목이 있으면 날짜를 둘째 줄로
        return recording.title == nil ? status : "\(RecordingFormat.day.string(from: recording.date)) · \(status)"
    }
}

private struct RecordingDetailView: View {
    let recording: Recording
    @ObservedObject var controller: RecordingController
    @ObservedObject var player: RecordingPlayer

    @State private var mode = Mode.conversation
    @State private var transcript: Transcript?
    @State private var plainText = ""
    @State private var copied = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    enum Mode: String, CaseIterable { case conversation = "대화", text = "텍스트" }

    private var isCurrent: Bool { controller.currentRecordingID == recording.id }
    private var transcribing: Bool { controller.transcriptionState(of: recording.id) == .running }
    private var queued: Bool { controller.transcriptionState(of: recording.id) == .queued }
    private var failed: Bool { controller.transcriptionState(of: recording.id) == .failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            Divider()
            if isCurrent {
                placeholder("녹음 중입니다. 정지하면 재생과 전사를 할 수 있습니다.", symbol: "record.circle")
            } else {
                playerBar.padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
                transcriptArea
            }
        }
        .onAppear {
            titleDraft = recording.title ?? ""
            loadTranscript()
        }
        .onChange(of: titleFocused) { _, focused in if !focused { saveTitle() } }
        .onDisappear(perform: saveTitle)
        .onChange(of: controller.transcribing) { _, _ in loadTranscript() }
    }

    // MARK: 머리글

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("제목 없음", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .focused($titleFocused)
                    .onSubmit { titleFocused = false }
                    .disabled(recording.meta == nil)
                    .help("클릭해서 제목 입력")
                Text(detailLine).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Button { controller.reveal(recording) } label: { Label("Finder", systemImage: "folder") }
            Button(role: .destructive) { confirmDelete() } label: { Label("삭제", systemImage: "trash") }
                .disabled(isCurrent || transcribing)
        }
    }

    private var detailLine: String {
        let date = RecordingFormat.full.string(from: recording.date)
        if isCurrent { return "\(date) · 녹음 중" }
        return recording.meta.map { "\(date) · 길이 \(RecordingFormat.duration($0.duration))" } ?? date
    }

    private func saveTitle() {
        controller.setTitle(titleDraft, for: recording)
    }

    // MARK: 재생

    private var playerBar: some View {
        HStack(spacing: 12) {
            Button(action: player.toggle) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 18)
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!player.canPlay)
            Text(RecordingFormat.duration(player.current)).monospacedDigit().font(.callout)
            Slider(value: Binding(get: { player.current }, set: { player.seek(to: $0) }),
                   in: 0...max(player.duration, 0.1))
                .disabled(!player.canPlay)
            Text(RecordingFormat.duration(player.duration)).monospacedDigit().font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: 전사

    @ViewBuilder
    private var transcriptArea: some View {
        if transcribing {
            placeholder("전사 중… (기기 안에서 처리합니다)", symbol: nil)
        } else if queued {
            placeholder("전사 대기 중… 앞의 녹음을 먼저 전사하고 있습니다", symbol: "hourglass")
        } else if !recording.hasTranscript {
            VStack(spacing: 12) {
                Image(systemName: failed ? "exclamationmark.bubble" : "text.bubble").font(.system(size: 34)).foregroundStyle(.secondary)
                Text(failed ? "전사에 실패했습니다" : "아직 전사하지 않았습니다").foregroundStyle(.secondary)
                Button(failed ? "다시 전사" : "전사하기") { controller.transcribe(recording) }
                    .controlSize(.large).keyboardShortcut(.defaultAction)
                    .disabled(recording.meta == nil)
                Text("Apple 기기 내 음성 인식 · 한국어").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                    Button(copied ? "복사됨" : "전체 복사", systemImage: copied ? "checkmark" : "doc.on.doc", action: copyAll)
                    Menu {
                        Button("다시 전사") { controller.transcribe(recording) }
                        Button("transcript.txt 열기") { controller.openTranscript(recording) }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
                if mode == .conversation, let transcript {
                    ConversationView(lines: TranscriptLine.lines(from: transcript), player: player)
                } else {
                    ScrollView {
                        Text(plainText).textSelection(.enabled)
                            .font(.body).lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String, symbol: String?) -> some View {
        VStack(spacing: 10) {
            if let symbol { Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.secondary) }
            else { ProgressView() }
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 동작

    private func loadTranscript() {
        transcript = recording.loadTranscript()
        plainText = (try? String(contentsOf: recording.transcriptURL, encoding: .utf8)) ?? ""
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "이 녹음을 휴지통으로 옮길까요?"
        alert.informativeText = "\(RecordingFormat.full.string(from: recording.date)) — 오디오와 전사 파일이 모두 휴지통으로 이동합니다. 휴지통에서 되살릴 수 있습니다."
        alert.addButton(withTitle: "휴지통으로 이동")
        alert.addButton(withTitle: "취소")
        if alert.runModal() == .alertFirstButtonReturn {
            player.load(nil)
            controller.moveToTrash(recording)
        }
    }
}

/// 대화 보기: 시각을 누르면 그 지점부터 재생, 재생 중인 줄은 강조.
private struct ConversationView: View {
    let lines: [TranscriptLine]
    @ObservedObject var player: RecordingPlayer

    private var currentLineID: Int? {
        guard player.isPlaying || player.current > 0 else { return nil }
        return lines.last { $0.start <= player.current }?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Button(RecordingFormat.duration(line.start)) {
                                player.seek(to: line.start)
                                if !player.isPlaying { player.play() }
                            }
                            .buttonStyle(.link).font(.callout.monospacedDigit())
                            .help("여기부터 재생")
                            Text(line.speaker)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(line.isMe ? Color.blue : Color.orange)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill((line.isMe ? Color.blue : Color.orange).opacity(0.12)))
                            Text(line.text).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(line.id == currentLineID ? 0.12 : 0)))
                        .id(line.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: currentLineID) { _, id in
                if let id, player.isPlaying { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }
}

// MARK: - 데이터

struct TranscriptLine: Identifiable {
    let id: Int
    let start: TimeInterval
    let speaker: String
    let text: String
    var isMe: Bool { speaker == "나" }

    static func lines(from transcript: Transcript) -> [TranscriptLine] {
        transcript.tracks
            .flatMap { track in track.segments.map { (track.speaker, $0) } }
            .sorted { $0.1.start < $1.1.start }
            .enumerated()
            .map { TranscriptLine(id: $0.offset, start: $0.element.1.start, speaker: $0.element.0, text: $0.element.1.text) }
    }
}

extension Recording {
    func loadTranscript() -> Transcript? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: folder.appendingPathComponent("transcript-apple.json")))
            .flatMap { try? decoder.decode(Transcript.self, from: $0) }
    }
}

enum RecordingFormat {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E) HH:mm"
        return f
    }()

    static let full: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 (E) HH:mm"
        return f
    }()

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(seconds, 0).rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
