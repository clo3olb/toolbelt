import AppKit
import ApplicationServices

/// 팝오버에 보여줄 상태와 동작. 팝오버를 열 때 refreshAll(), 열려 있는 동안 2초마다 시스템 사용량만 갱신한다.
@MainActor
final class PanelModel: ObservableObject {
    struct Usage {
        let ratio: Double?
        let detail: String
    }

    @Published var cpu = Usage(ratio: nil, detail: "측정 중…")
    @Published var memory = Usage(ratio: nil, detail: "")
    @Published var storage = Usage(ratio: nil, detail: "")
    @Published var displays: [DisplayInfo] = []
    @Published var hasDisabledDisplays = false
    @Published var trusted = false
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var capsLockSwitch = false
    @Published var capsShortcutReady = false
    @Published var volumes: [StorageVolume] = []
    /// CPU 온도(°C), 팬, 발열 상태 — 온도·팬은 SMC(비공개)라 못 읽으면 nil/빈 배열
    @Published var cpuTemperature: Double?
    @Published var fans: [SMC.Fan] = []
    @Published var thermalState: ProcessInfo.ThermalState = .nominal

    /// PanelController가 채운다: 팝오버 닫기 / 팝오버를 열기 전 앞에 있던 앱으로 돌아가 실행
    var dismiss: () -> Void = {}
    var runInPreviousApp: (@escaping () -> Void) -> Void = { $0() }

    private var timer: Timer?
    private var volumeObservers: [NSObjectProtocol] = []

    init() {
        // 디스크를 꽂거나 뽑으면 바로 갱신
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.volumes = StorageDevices.volumes() }
            })
        }
    }

    var activeDisplayCount: Int { displays.filter(\.isActive).count }

    // MARK: - 갱신

    func refreshAll() {
        displays = DisplayManager.displays()
        hasDisabledDisplays = DisplayManager.hasDisabledDisplays
        trusted = AXIsProcessTrusted()
        loginEnabled = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
        capsLockSwitch = CapsLockSwitch.isEnabled
        capsShortcutReady = CapsLockSwitch.isShortcutF19
        // CPU는 두 시점의 차이로 계산한다. 직전에 닫은 뒤의 긴 평균이 보이지 않도록 기준점만 새로 잡는다.
        _ = SystemStats.cpuUsage()
        refreshStats(cpu: false)
    }

    func startUpdating() {
        stopUpdating()
        // 첫 CPU 값은 0.5초 뒤에 바로 보여주고 이후 2초마다. 팝오버 이벤트 추적 중에도 돌도록 .common 모드.
        let timer = Timer(fire: Date().addingTimeInterval(0.5), interval: 2, repeats: true) { [weak self] _ in
            self?.refreshStats(cpu: true)
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopUpdating() {
        timer?.invalidate()
        timer = nil
    }

    /// SMC는 처음에 센서 키를 찾느라 잠깐 걸리므로 백그라운드에서 읽는다
    private func refreshThermals() {
        thermalState = ProcessInfo.processInfo.thermalState
        DispatchQueue.global(qos: .utility).async {
            let temperature = SMC.shared.cpuTemperature()
            let fans = SMC.shared.fans()
            DispatchQueue.main.async { [weak self] in
                self?.cpuTemperature = temperature
                self?.fans = fans
            }
        }
    }

    private func refreshStats(cpu measure: Bool) {
        refreshThermals()
        if measure, let ratio = SystemStats.cpuUsage() {
            cpu = Usage(ratio: ratio, detail: "전체 코어")
        } else if !measure {
            cpu = Usage(ratio: nil, detail: "측정 중…")
        }
        if let m = SystemStats.memory() {
            memory = Usage(ratio: Double(m.used) / Double(m.total),
                           detail: "\(gigabytes(Double(m.used), unit: 1_073_741_824)) / \(gigabytes(Double(m.total), unit: 1_073_741_824)) GB")
        }
        volumes = StorageDevices.volumes()
        if let s = SystemStats.storage() {
            storage = Usage(ratio: Double(s.used) / Double(s.total),
                            detail: "\(gigabytes(Double(s.used), unit: 1e9)) / \(gigabytes(Double(s.total), unit: 1e9)) GB")
        }
    }

    /// GB 숫자만. 메모리는 2진(2^30), 저장 공간은 Finder와 같은 10진(10^9). 100 이상은 소수점 없이.
    private func gigabytes(_ bytes: Double, unit: Double) -> String {
        let value = bytes / unit
        return value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    // MARK: - 동작

    func snap(_ action: SnapAction) {
        runInPreviousApp { WindowMover.perform(action) }
    }

    /// 디스플레이 동작은 확인/오류 다이얼로그를 띄우므로 팝오버를 먼저 닫는다.
    func displayAction(_ work: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    func setLoginEnabled(_ on: Bool) {
        if on != LoginItem.isEnabled { LoginItem.toggle() }
        loginEnabled = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
    }

    func setCapsLockSwitch(_ on: Bool) {
        CapsLockSwitch.isEnabled = on
        capsLockSwitch = on
    }

    func openShortcutSettings() {
        dismiss()
        CapsLockSwitch.openShortcutSettings()
    }

    func openAccessibilitySettings() {
        dismiss()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openMainWindow(_ page: MainPage?) {
        dismiss()
        MainWindowController.shared.show(page)
    }

    func reveal(_ volume: StorageVolume) {
        dismiss()
        StorageDevices.reveal(volume)
    }

    /// 꺼내기는 시간이 걸릴 수 있어 백그라운드에서 하고, 실패하면 알린다.
    func eject(_ volume: StorageVolume) {
        dismiss()
        DispatchQueue.global(qos: .userInitiated).async {
            let message = StorageDevices.eject(volume)
            DispatchQueue.main.async {
                self.volumes = StorageDevices.volumes()
                guard let message else { return }
                NSApp.activate()
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "꺼내기 실패"
                alert.informativeText = message
                alert.runModal()
            }
        }
    }

    func openActivityMonitor() {
        dismiss()
        SystemStats.openActivityMonitor()
    }
}
