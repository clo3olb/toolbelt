import AppKit
import Carbon.HIToolbox

/// 창 배치 종류별 켜기/끄기와 단축키. 바뀌면 전역 단축키를 다시 등록한다.
///   UserDefaults "snapEnabled": [rawValue], "snapHotKeys": {rawValue: HotKey}
@MainActor
final class WindowSnapSettings: ObservableObject {
    static let shared = WindowSnapSettings()

    private static let enabledKey = "snapEnabled"
    private static let hotKeysKey = "snapHotKeys"
    private static let group = "windowSnap"
    /// 다른 기능이 쓰는 키 — 창 배치에 지정하지 못하게 막는다
    static let reserved: [HotKey] = [
        HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: HotKey.controlOptionCommand),  // 디스플레이 비상 복구
    ]

    @Published private(set) var enabled: Set<SnapAction>
    @Published private(set) var hotKeys: [SnapAction: HotKey]

    /// 켜져 있는 종류 (목록 순서)
    var enabledActions: [SnapAction] { SnapAction.allCases.filter { enabled.contains($0) } }

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.stringArray(forKey: Self.enabledKey) {
            enabled = Set(raw.compactMap(SnapAction.init(rawValue:)))
        } else {
            enabled = Set(SnapAction.allCases.filter { $0.defaultHotKey != nil })
        }
        if let data = defaults.data(forKey: Self.hotKeysKey),
           let decoded = try? JSONDecoder().decode([String: HotKey].self, from: data) {
            hotKeys = Dictionary(uniqueKeysWithValues: decoded.compactMap { k, v in SnapAction(rawValue: k).map { ($0, v) } })
        } else {
            hotKeys = Dictionary(uniqueKeysWithValues: SnapAction.allCases.compactMap { a in a.defaultHotKey.map { (a, $0) } })
        }
    }

    // MARK: - 변경

    func isEnabled(_ action: SnapAction) -> Bool { enabled.contains(action) }

    func setEnabled(_ action: SnapAction, _ on: Bool) {
        if on { enabled.insert(action) } else { enabled.remove(action) }
        save()
    }

    /// 단축키 지정. 다른 종류가 같은 키를 쓰고 있으면 그쪽은 비운다. 예약된 키면 거부하고 메시지를 돌려준다.
    @discardableResult
    func setHotKey(_ hotKey: HotKey?, for action: SnapAction) -> String? {
        if let hotKey {
            if Self.reserved.contains(hotKey) { return "\(hotKey.display)는 다른 기능이 쓰는 단축키입니다." }
            if let other = hotKeys.first(where: { $0.value == hotKey && $0.key != action })?.key {
                hotKeys[other] = nil
                hotKeys[action] = hotKey
                enabled.insert(action)
                save()
                return "\(hotKey.display)를 '\(other.title)'에서 옮겼습니다."
            }
            hotKeys[action] = hotKey
            enabled.insert(action)
        } else {
            hotKeys[action] = nil
        }
        save()
        return nil
    }

    func resetToDefaults() {
        enabled = Set(SnapAction.allCases.filter { $0.defaultHotKey != nil })
        hotKeys = Dictionary(uniqueKeysWithValues: SnapAction.allCases.compactMap { a in a.defaultHotKey.map { (a, $0) } })
        save()
    }

    // MARK: - 전역 단축키

    /// 켜져 있고 단축키가 있는 종류만 등록
    func applyHotKeys() {
        let commands = enabledActions.compactMap { action -> Command? in
            guard let hotKey = hotKeys[action] else { return nil }
            return Command(title: action.title, hotKey: hotKey, run: { WindowMover.perform(action) })
        }
        HotKeyCenter.replaceGroup(Self.group, with: commands)
    }

    /// 단축키를 기록하는 동안 잠시 해제 (등록된 키를 누르면 기록 대신 창이 움직이므로)
    func suspendHotKeys() {
        HotKeyCenter.removeGroup(Self.group)
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(enabled.map(\.rawValue), forKey: Self.enabledKey)
        let raw = Dictionary(uniqueKeysWithValues: hotKeys.map { ($0.key.rawValue, $0.value) })
        defaults.set(try? JSONEncoder().encode(raw), forKey: Self.hotKeysKey)
        applyHotKeys()
    }
}
