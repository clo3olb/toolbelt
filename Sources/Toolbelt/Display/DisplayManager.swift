import AppKit
import CoreGraphics

/// 비공개 API: 디스플레이를 소프트웨어적으로 연결 해제/재연결한다 (BetterDisplay의 Disconnect와 같은 방식).
/// macOS 업데이트로 동작이 바뀔 수 있다.
@_silgen_name("CGSConfigureDisplayEnabled")
private func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef?, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

struct DisplayInfo {
    let id: CGDirectDisplayID
    let name: String
    let isActive: Bool
    let isMain: Bool
}

enum DisplayManager {
    /// 연결 해제한 디스플레이 기록 [displayID: 이름]. 앱을 재시작해도 다시 연결할 수 있도록 저장한다.
    private static let storeKey = "disabledDisplays"
    private static let confirmSeconds = 15

    // MARK: - 조회

    static func displays() -> [DisplayInfo] {
        let active = activeDisplayIDs()
        var store = disabledStore
        // 물리적으로 다시 꽂는 등 이미 활성화된 디스플레이는 기록에서 제거
        for id in active { store[id] = nil }
        disabledStore = store

        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let id = screen.displayID { names[id] = screen.localizedName }
        }
        let main = CGMainDisplayID()
        let activeInfos = active.map {
            DisplayInfo(id: $0, name: names[$0] ?? "디스플레이 \($0)", isActive: true, isMain: $0 == main)
        }
        let disabledInfos = store.sorted { $0.key < $1.key }.map {
            DisplayInfo(id: $0.key, name: $0.value, isActive: false, isMain: false)
        }
        return activeInfos + disabledInfos
    }

    static var hasDisabledDisplays: Bool { !disabledStore.isEmpty }

    // MARK: - 연결 해제 / 재연결

    static func disconnect(_ display: DisplayInfo) {
        // 안전장치 1: 마지막 남은 디스플레이는 끌 수 없다
        guard activeDisplayIDs().count > 1 else {
            showError("마지막 남은 디스플레이는 연결 해제할 수 없습니다.")
            return
        }
        var store = disabledStore
        store[display.id] = display.name
        disabledStore = store

        let err = setEnabled(display.id, false)
        guard err == .success else {
            store[display.id] = nil
            disabledStore = store
            showError("\(display.name) 연결 해제 실패 (CGError \(err.rawValue))")
            return
        }

        // 안전장치 2: 화면 재구성이 끝난 뒤 확인을 받고, 응답이 없으면 자동으로 되돌린다
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if !confirmKeep(display.name) { reconnect(display.id) }
        }
    }

    @discardableResult
    static func reconnect(_ id: CGDirectDisplayID) -> Bool {
        let err = setEnabled(id, true)
        if err == .success {
            var store = disabledStore
            store[id] = nil
            disabledStore = store
            return true
        }
        NSLog("Toolbelt: 디스플레이 \(id) 재연결 실패 (CGError \(err.rawValue))")
        return false
    }

    /// 비상 복구용: 기록된 모든 디스플레이를 다시 연결한다.
    static func reconnectAll() {
        let failed = disabledStore.filter { !reconnect($0.key) }
        if !failed.isEmpty {
            showError("다시 연결하지 못한 디스플레이: \(failed.values.joined(separator: ", "))\n케이블을 뺐다 꽂거나 로그아웃하면 복구됩니다.")
        }
    }

    // MARK: - 주 디스플레이

    /// 지정한 디스플레이의 원점을 (0,0)으로 옮겨 주 디스플레이로 만든다. 상대 배치는 유지된다.
    static func makeMain(_ display: DisplayInfo) {
        guard display.isActive, !display.isMain else { return }
        let origin = CGDisplayBounds(display.id).origin
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        for id in activeDisplayIDs() {
            let b = CGDisplayBounds(id).origin
            CGConfigureDisplayOrigin(config, id, Int32(b.x - origin.x), Int32(b.y - origin.y))
        }
        let err = CGCompleteDisplayConfiguration(config, .permanently)
        if err != .success { showError("주 디스플레이 변경 실패 (CGError \(err.rawValue))") }
    }

    // MARK: - 내부

    private static func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) -> CGError {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else { return begin }
        let err = CGSConfigureDisplayEnabled(config, id, enabled)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            return err
        }
        // 안전장치 3: forSession — 로그아웃/재부팅하면 원래대로 돌아온다
        return CGCompleteDisplayConfiguration(config, .forSession)
    }

    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    private static var disabledStore: [CGDirectDisplayID: String] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String] ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UInt32(k).map { ($0, v) } })
        }
        set {
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) }), forKey: storeKey)
        }
    }

    private static func confirmKeep(_ name: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(name) 연결 해제를 유지할까요?"
        alert.addButton(withTitle: "유지")
        alert.addButton(withTitle: "되돌리기")
        var remaining = confirmSeconds
        func update() { alert.informativeText = "\(remaining)초 안에 응답하지 않으면 자동으로 다시 연결합니다.\n비상 복구: ⌃⌥⌘R" }
        update()
        let timer = Timer(timeInterval: 1, repeats: true) { t in
            remaining -= 1
            update()
            if remaining <= 0 {
                t.invalidate()
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        let response = alert.runModal()
        timer.invalidate()
        return response == .alertFirstButtonReturn
    }

    private static func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Toolbelt 디스플레이"
        alert.informativeText = message
        alert.runModal()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
