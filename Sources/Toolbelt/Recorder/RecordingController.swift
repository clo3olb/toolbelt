import AppKit
import AVFoundation

/// 녹음 상태와 동작. 팝오버가 닫혀 있어도 녹음은 계속되므로 앱 전역에 하나만 둔다.
@MainActor
final class RecordingController: ObservableObject {
    static let shared = RecordingController()

    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var recordings: [Recording] = []
    /// 지금 전사 중인 녹음 (한 번에 하나)
    @Published private(set) var transcribing: Set<String> = []
    /// 전사 대기열 (녹음이 끝나면 자동으로 들어온다)
    @Published private(set) var transcriptionQueue: [String] = []
    /// 전사에 실패한 녹음 — 자동으로 다시 시도하지 않고 사용자가 "전사"를 누르면 다시 한다
    @Published private(set) var transcriptionFailed: Set<String> = []
    @Published var errorMessage: String?
    /// 화면 및 시스템 오디오 녹음 권한 문제로 실패했을 때 설정 바로가기를 보여준다
    @Published private(set) var needsScreenPermission = false
    /// 녹음 중인 폴더 이름 (목록에서 "녹음 중" 표시, 삭제 방지)
    @Published private(set) var currentRecordingID: String?
    /// 통화 자동 녹음 켜짐 여부 (기본 꺼짐 — 통화 상대가 있으므로 사용자가 직접 켠다)
    @Published private(set) var autoRecordCalls = UserDefaults.standard.object(forKey: "autoRecordCalls") as? Bool ?? false
    /// 자동 녹음 중인 통화 이름 (예: "카카오톡"). 직접 시작한 녹음이면 nil.
    @Published private(set) var autoCallName: String?
    /// 자동 녹음 중 통화가 끝난 것으로 보여 곧 정지할 예정
    @Published private(set) var autoCallEnding = false

    private var recorder: AudioRecorder?
    private var folder: URL?
    private var startedAt: Date?
    private var timer: Timer?
    private let callDetector = CallDetector()

    private static let titleTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private init() {
        reload()
        callDetector.onCallStarted = { [weak self] call in self?.callStarted(call) }
        callDetector.onCallEnded = { [weak self] _ in self?.callEnded() }
        callDetector.onCallEnding = { [weak self] ending in self?.autoCallEnding = ending }
    }

    /// 앱 시작 시 호출: 통화 감지 시작 + 아직 전사 안 된 녹음을 자동 전사 대기열에 넣는다
    func startServices() {
        if autoRecordCalls { callDetector.start() }
        for recording in recordings.reversed() where needsTranscription(recording) {
            enqueueTranscription(recording.id)
        }
    }

    private func needsTranscription(_ recording: Recording) -> Bool {
        !recording.hasTranscript && recording.id != currentRecordingID && (recording.meta?.duration ?? 0) >= 1
    }

    // MARK: - 통화 자동 녹음

    func setAutoRecordCalls(_ on: Bool) {
        autoRecordCalls = on
        UserDefaults.standard.set(on, forKey: "autoRecordCalls")
        on ? callDetector.start() : callDetector.stop()
    }

    /// 통화 앱이 마이크를 쓰기 시작함 → 녹음 중이 아니면 "앱 · 시각" 제목으로 녹음 시작
    private func callStarted(_ call: CallDetector.Call) {
        guard autoRecordCalls, !isRecording, !isStarting else { return }
        autoCallName = call.name
        start(title: "\(call.name) 통화 녹음 · \(Self.titleTime.string(from: Date()))")
    }

    /// 통화 끝 → 자동으로 시작한 녹음만 멈춘다 (직접 시작한 녹음은 그대로)
    private func callEnded() {
        guard autoCallName != nil else { return }
        stop()
    }

    func reload() {
        recordings = RecordingStore.all()
    }

    // MARK: - 녹음

    func toggle() {
        isRecording ? stop() : start()
    }

    func start(title: String? = nil) {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        errorMessage = nil
        needsScreenPermission = false
        Task {
            defer { isStarting = false }
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                autoCallName = nil
                errorMessage = "마이크 권한이 필요합니다. 시스템 설정 → 개인정보 보호 및 보안 → 마이크에서 Toolbelt를 허용하세요."
                return
            }
            let now = Date()
            var createdFolder: URL?
            do {
                let folder = try RecordingStore.makeFolder(for: now)
                createdFolder = folder
                let recorder = AudioRecorder()
                recorder.onStop = { [weak self] error in
                    self?.errorMessage = "녹음이 중단됐습니다: \(error?.localizedDescription ?? "알 수 없는 오류")"
                    self?.stop()
                }
                try await recorder.start(in: folder)
                self.recorder = recorder
                self.folder = folder
                self.startedAt = now
                // 녹음 중에도 제목을 적을 수 있도록 meta.json을 먼저 만든다 (정지할 때 길이·offset을 채운다)
                RecordingStore.saveMeta(RecordingMeta(startedAt: now, duration: 0, title: title), in: folder)
                currentRecordingID = folder.lastPathComponent
                isRecording = true
                reload()
                elapsed = 0
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let startedAt = self.startedAt else { return }
                        self.elapsed = Date().timeIntervalSince(startedAt)
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            } catch {
                // 화면 녹음 권한이 없으면 SCShareableContent가 실패한다
                needsScreenPermission = true
                autoCallName = nil
                errorMessage = "녹음을 시작하지 못했습니다. '화면 및 시스템 오디오 녹음'에서 Toolbelt를 허용한 뒤 Toolbelt를 다시 실행하세요.\n(\(error.localizedDescription))"
                if let createdFolder { try? removeIfEmpty(createdFolder) }
            }
        }
    }

    func stop() {
        guard isRecording, let recorder, let folder, let startedAt else { return }
        isRecording = false
        autoCallName = nil
        autoCallEnding = false
        timer?.invalidate()
        timer = nil
        self.recorder = nil
        Task {
            let result = await recorder.stop()
            saveFinalMeta(result, startedAt: startedAt, in: folder)
            currentRecordingID = nil
            reload()
            // 로컬에서 처리하므로 끝나면 바로 자동 전사
            if let recording = recordings.first(where: { $0.folder == folder }), needsTranscription(recording) {
                enqueueTranscription(recording.id)
            }
        }
    }

    /// 앱 종료 전에 녹음 중이면 파일을 마무리한다.
    func finishForQuit() async {
        guard isRecording, let recorder, let folder, let startedAt else { return }
        isRecording = false
        timer?.invalidate()
        let result = await recorder.stop()
        saveFinalMeta(result, startedAt: startedAt, in: folder)
    }

    /// 녹음 중에 적은 제목은 유지한다.
    private func saveFinalMeta(_ result: AudioRecorder.Result, startedAt: Date, in folder: URL) {
        let title = recordings.first { $0.folder == folder }?.meta?.title
        RecordingStore.saveMeta(RecordingMeta(startedAt: startedAt, duration: result.duration,
                                              micOffset: result.micOffset, systemOffset: result.systemOffset,
                                              title: title),
                                in: folder)
    }

    private func removeIfEmpty(_ folder: URL) throws {
        let items = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        if items.isEmpty { try FileManager.default.removeItem(at: folder) }
    }

    // MARK: - 전사

    enum TranscriptionState { case none, queued, running, failed }

    func transcriptionState(of id: String) -> TranscriptionState {
        if transcribing.contains(id) { return .running }
        if transcriptionQueue.contains(id) { return .queued }
        if transcriptionFailed.contains(id) { return .failed }
        return .none
    }

    /// 수동 전사 / 다시 전사 — 대기열 맨 앞에 넣는다
    func transcribe(_ recording: Recording) {
        transcriptionFailed.remove(recording.id)
        enqueueTranscription(recording.id, first: true)
    }

    private func enqueueTranscription(_ id: String, first: Bool = false) {
        guard !transcribing.contains(id), !transcriptionQueue.contains(id) else { return }
        first ? transcriptionQueue.insert(id, at: 0) : transcriptionQueue.append(id)
        processTranscriptionQueue()
    }

    /// 한 번에 하나씩 순서대로 전사한다.
    private func processTranscriptionQueue() {
        guard transcribing.isEmpty, !transcriptionQueue.isEmpty else { return }
        let id = transcriptionQueue.removeFirst()
        guard let recording = recordings.first(where: { $0.id == id }) else {
            processTranscriptionQueue()
            return
        }
        transcribing.insert(id)
        Task {
            do {
                try await RecordingTranscriber.transcribe(recording)
            } catch {
                transcriptionFailed.insert(id)
                errorMessage = "전사 실패 (\(recording.title ?? recording.id)): \(error.localizedDescription)"
            }
            transcribing.remove(id)
            reload()
            processTranscriptionQueue()
        }
    }

    // MARK: - 관리

    func setTitle(_ title: String, for recording: Recording) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // 디스크의 최신 meta를 기준으로 제목만 바꾼다
        guard var meta = RecordingStore.all().first(where: { $0.id == recording.id })?.meta,
              (meta.title ?? "") != trimmed else { return }
        meta.title = trimmed.isEmpty ? nil : trimmed
        RecordingStore.saveMeta(meta, in: recording.folder)
        reload()
    }

    /// 휴지통으로 이동 (되살릴 수 있음). 녹음 중이거나 전사 중인 녹음은 옮기지 않는다.
    func moveToTrash(_ recording: Recording) {
        guard recording.id != currentRecordingID, !transcribing.contains(recording.id) else { return }
        transcriptionQueue.removeAll { $0 == recording.id }
        do {
            try FileManager.default.trashItem(at: recording.folder, resultingItemURL: nil)
        } catch {
            errorMessage = "휴지통으로 옮기지 못했습니다: \(error.localizedDescription)"
        }
        reload()
    }

    // MARK: - 열기

    func openTranscript(_ recording: Recording) {
        NSWorkspace.shared.open(recording.transcriptURL)
    }

    func reveal(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.folder])
    }

    func openScreenPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
