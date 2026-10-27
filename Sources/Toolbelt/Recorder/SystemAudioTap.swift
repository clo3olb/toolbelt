import AVFoundation
import CoreAudio

/// 컴퓨터에서 나는 소리를 Core Audio 프로세스 탭으로 받아 system.m4a에 기록한다.
///
/// ScreenCaptureKit의 시스템 오디오에는 Mac 전화 앱(iPhone 연속성 통화) 소리가 들어오지 않았다(2026-10-21, 25분 무음).
/// 프로세스 탭은 모든 프로세스의 출력을 Core Audio에서 직접 가로채므로 시스템 데몬이 내는 통화 소리도 받는다.
/// Toolbelt 자신의 소리(녹음 재생)는 제외한다. 권한은 '시스템 오디오 녹음'(NSAudioCaptureUsageDescription).
final class SystemAudioTap {
    private let url: URL
    private let queue = DispatchQueue(label: "kr.clo3olb.toolbelt.systemtap")
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var format: AVAudioFormat?
    /// 호스트 시계 기준 (ScreenCaptureKit 마이크 샘플 시각과 같은 시계)
    private(set) var firstPTS: CMTime?
    private(set) var lastPTS: CMTime?

    init(url: URL) { self.url = url }

    func start() throws {
        let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcessObjects())
        tap.uuid = UUID()
        tap.name = "Toolbelt 녹음"
        tap.isPrivate = true
        tap.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(tap, &tapID), "탭 생성")

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd), "탭 형식")
        guard let format = AVAudioFormat(streamDescription: &asbd) else { throw TapError.failed("탭 형식") }
        self.format = format

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Toolbelt 녹음",
            kAudioAggregateDeviceUIDKey: "kr.clo3olb.toolbelt.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tap.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID), "집합 장치 생성")

        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: min(format.channelCount, 2),
            AVEncoderBitRateKey: 64_000 * Int(min(format.channelCount, 2)),
        ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)

        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, inputTime, _, _ in
            self?.write(input, at: inputTime.pointee)
        }, "IOProc 생성")
        try check(AudioDeviceStart(aggregateID, procID), "시작")
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        queue.sync {
            file?.close()
            file = nil
        }
        // 샘플이 하나도 없으면 빈 파일을 남기지 않는다
        if firstPTS == nil { try? FileManager.default.removeItem(at: url) }
    }

    private func write(_ input: UnsafePointer<AudioBufferList>, at time: AudioTimeStamp) {
        guard let file, let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil),
              buffer.frameLength > 0 else { return }
        do { try file.write(from: buffer) } catch { return }
        let start = time.mFlags.contains(.hostTimeValid)
            ? CMTime(value: CMTimeValue(AudioConvertHostTimeToNanos(time.mHostTime)), timescale: 1_000_000_000)
            : CMClockGetTime(CMClockGetHostTimeClock())
        if firstPTS == nil { firstPTS = start }
        lastPTS = start + CMTime(value: CMTimeValue(buffer.frameLength), timescale: CMTimeScale(format.sampleRate))
    }

    /// Toolbelt 자신의 Core Audio 프로세스 객체 (아직 소리를 낸 적이 없으면 비어 있을 수 있다)
    private static func ownProcessObjects() -> [AudioObjectID] {
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? [object] : []
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        if status != noErr { throw TapError.failed("\(step) (\(status))") }
    }

    enum TapError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            if case .failed(let step) = self { return "시스템 오디오 탭 실패: \(step)" }
            return nil
        }
    }
}
