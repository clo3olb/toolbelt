import AVFoundation
import ScreenCaptureKit

/// 마이크와 컴퓨터 소리를 ScreenCaptureKit 한 스트림으로 받아 **각각 다른 파일**로 저장한다.
///   mic.m4a    — 내 마이크 (SCStreamOutputType.microphone)
///   system.m4a — 컴퓨터에서 나는 소리. Core Audio 프로세스 탭(SystemAudioTap)으로 받고,
///                탭을 만들 수 없으면 SCStreamOutputType.audio로 받는다. Toolbelt 자신의 소리는 제외.
/// 두 트랙은 같은 호스트 시계를 쓰므로 첫 샘플 시각 차이(offset)를 저장해 두면 전사 결과를 시간순으로 합칠 수 있다.
final class AudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    struct Result {
        let duration: TimeInterval
        /// 녹음 시작(두 트랙 중 먼저 들어온 샘플) 기준 각 트랙의 시작 시각(초). 샘플이 없던 트랙은 nil.
        let micOffset: TimeInterval?
        let systemOffset: TimeInterval?
    }

    private let queue = DispatchQueue(label: "kr.clo3olb.toolbelt.recorder")
    private var stream: SCStream?
    private var mic: TrackWriter?
    private var system: TrackWriter?
    private var tap: SystemAudioTap?
    /// 녹음 중 스트림이 끊기면 호출 (권한 해제, 디스플레이 변경 등)
    var onStop: ((Error?) -> Void)?

    func start(in folder: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw RecorderError.noDisplay }

        let systemURL = folder.appendingPathComponent(RecordingStore.systemFile)
        let tap = SystemAudioTap(url: systemURL)
        do {
            try tap.start()
            self.tap = tap
        } catch {
            tap.stop()
            NSLog("Toolbelt: \(error.localizedDescription) — ScreenCaptureKit 시스템 오디오로 녹음")
            system = TrackWriter(url: systemURL)
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = self.tap == nil
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = true
        config.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        config.sampleRate = 48_000
        config.channelCount = 2
        // 화면은 필요 없지만 스트림에 디스플레이가 있어야 하므로 최소 크기·최저 빈도로 받는다
        config.width = 16
        config.height = 16
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        mic = TrackWriter(url: folder.appendingPathComponent(RecordingStore.micFile))

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        do {
            try await stream.startCapture()
        } catch {
            self.tap?.stop()
            self.tap = nil
            throw error
        }
        self.stream = stream
    }

    func stop() async -> Result {
        if let stream { try? await stream.stopCapture() }
        stream = nil
        let (mic, system) = queue.sync { (self.mic, self.system) }
        await mic?.finish()
        await system?.finish()
        tap?.stop()
        self.mic = nil
        self.system = nil

        let systemFirst = tap?.firstPTS ?? system?.firstPTS
        let systemLast = tap?.lastPTS ?? system?.lastPTS
        tap = nil
        let starts = [mic?.firstPTS, systemFirst].compactMap { $0 }
        let ends = [mic?.lastPTS, systemLast].compactMap { $0 }
        guard let start = starts.min(), let end = ends.max() else {
            return Result(duration: 0, micOffset: nil, systemOffset: nil)
        }
        return Result(duration: (end - start).seconds,
                      micOffset: mic?.firstPTS.map { ($0 - start).seconds },
                      systemOffset: systemFirst.map { ($0 - start).seconds })
    }

    // MARK: - SCStreamOutput / SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .microphone: mic?.append(sampleBuffer)
        case .audio: system?.append(sampleBuffer)
        default: break // 화면 프레임은 버린다
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onStop?(error) }
    }
}

enum RecorderError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "녹음할 디스플레이를 찾지 못했습니다."
        }
    }
}

/// 오디오 샘플 버퍼를 AAC(.m4a)로 기록한다. 첫 샘플의 형식에 맞춰 지연 생성한다.
private final class TrackWriter {
    let url: URL
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private(set) var firstPTS: CMTime?
    private(set) var lastPTS: CMTime?

    init(url: URL) { self.url = url }

    func append(_ buffer: CMSampleBuffer) {
        guard buffer.isValid, buffer.numSamples > 0 else { return }
        if writer == nil, !setUp(for: buffer) { return }
        guard let writer, let input, writer.status != .failed else { return }

        let pts = buffer.presentationTimeStamp
        if firstPTS == nil {
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            firstPTS = pts
        }
        if input.isReadyForMoreMediaData, input.append(buffer) {
            lastPTS = pts + buffer.duration
        }
    }

    func finish() async {
        guard let writer, firstPTS != nil, writer.status == .writing else { return }
        input?.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            NSLog("Toolbelt: \(url.lastPathComponent) 저장 실패 — \(writer.error?.localizedDescription ?? "")")
        }
    }

    private func setUp(for buffer: CMSampleBuffer) -> Bool {
        guard let asbd = buffer.formatDescription?.audioStreamBasicDescription,
              let writer = try? AVAssetWriter(outputURL: url, fileType: .m4a) else { return false }
        let channels = Int(min(max(asbd.mChannelsPerFrame, 1), 2))
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: asbd.mSampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 64_000 * channels,
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        self.writer = writer
        self.input = input
        return true
    }
}
