import AVFoundation

/// mic.m4a와 system.m4a를 녹음 시작 기준 시간축에 맞춰 함께 재생한다.
@MainActor
final class RecordingPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var current: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var loadedID: String?

    private var tracks: [(player: AVAudioPlayer, offset: TimeInterval)] = []
    private var timer: Timer?
    /// 재생 시작 시점의 (기기 시각, current)
    private var anchor: (device: TimeInterval, position: TimeInterval)?

    func load(_ recording: Recording?) {
        guard recording?.id != loadedID else { return }
        stop()
        tracks = []
        current = 0
        duration = 0
        loadedID = recording?.id
        guard let recording else { return }
        let sources = [(recording.micURL, recording.meta?.micOffset), (recording.systemURL, recording.meta?.systemOffset)]
        for (url, offset) in sources {
            guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            tracks.append((player, offset ?? 0))
        }
        duration = recording.meta?.duration ?? tracks.map { $0.offset + $0.player.duration }.max() ?? 0
    }

    var canPlay: Bool { !tracks.isEmpty }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let clock = tracks.first?.player, !isPlaying else { return }
        if current >= duration { current = 0 }
        let startAt = clock.deviceCurrentTime + 0.05
        for (player, offset) in tracks {
            let local = current - offset
            if local >= player.duration { continue }
            player.currentTime = max(local, 0)
            // 아직 시작 전인 트랙은 그만큼 늦게 시작
            player.play(atTime: startAt + max(-local, 0))
        }
        anchor = (startAt, current)
        isPlaying = true
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        guard isPlaying else { return }
        updatePosition()
        tracks.forEach { $0.player.pause() }
        timer?.invalidate()
        timer = nil
        anchor = nil
        isPlaying = false
    }

    func stop() {
        pause()
        tracks.forEach { $0.player.stop() }
    }

    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying
        pause()
        current = min(max(time, 0), duration)
        if wasPlaying { play() }
    }

    /// 타이머: 위치를 갱신하고 끝에 닿으면 멈춘다.
    private func tick() {
        updatePosition()
        if isPlaying, current >= duration { pause() }
    }

    /// 위치만 갱신한다. pause()에서도 부르므로 여기서 pause()를 부르면 안 된다 (무한 재귀).
    private func updatePosition() {
        guard let anchor, let clock = tracks.first?.player else { return }
        current = min(anchor.position + max(clock.deviceCurrentTime - anchor.device, 0), duration)
    }
}
