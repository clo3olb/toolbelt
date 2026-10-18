import AppKit
import Carbon.HIToolbox
import IOKit.hid
import IOKit.hidsystem

/// Caps Lock 한/영 전환 (카라비너 대체).
///
/// Caps Lock을 F19로 리매핑하고, macOS "이전 입력 소스 선택" 단축키를 F19로 지정해 쓴다.
/// macOS의 Caps Lock 길게/짧게 판정이 없어져 누르는 즉시 전환된다. (대문자 고정은 쓰지 않음)
///
/// 리매핑은 세션 한정(재부팅 시 원복)이라 앱 실행 시마다 적용하고, 종료 시 제거한다.
enum CapsLockSwitch {
    private static let defaultsKey = "capsLockSwitch"

    // HID usage (page 0x07 키보드)
    private static let capsLockUsage: UInt64 = 0x7_0000_0039
    private static let f19Usage: UInt64 = 0x7_0000_006E

    static var isEnabled: Bool {
        // 키보드 동작을 바꾸는 기능이라 처음에는 꺼 둔다 (사용자가 켜야 적용)
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            newValue ? applyMapping() : removeMapping()
        }
    }

    /// 앱 시작 시 호출.
    static func start() {
        if isEnabled { applyMapping() }
    }

    /// 앱 종료 시 호출. Caps Lock을 원래대로 돌려놓는다.
    static func stop() {
        removeMapping()
    }

    // MARK: - 키 리매핑 (hidutil과 같은 UserKeyMapping)

    private static func applyMapping() {
        var mapping = currentMapping().filter { !isOurs($0) }
        mapping.append([kIOHIDKeyboardModifierMappingSrcKey: capsLockUsage,
                        kIOHIDKeyboardModifierMappingDstKey: f19Usage])
        setMapping(mapping)
    }

    private static func removeMapping() {
        setMapping(currentMapping().filter { !isOurs($0) })
    }

    /// 다른 도구가 넣어 둔 매핑은 건드리지 않도록 Caps Lock 원본 항목만 골라낸다.
    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry[kIOHIDKeyboardModifierMappingSrcKey] as? NSNumber)?.uint64Value == capsLockUsage
    }

    private static func currentMapping() -> [[String: Any]] {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        return IOHIDEventSystemClientCopyProperty(client, kIOHIDUserKeyUsageMapKey as CFString) as? [[String: Any]] ?? []
    }

    private static func setMapping(_ mapping: [[String: Any]]) {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        if !IOHIDEventSystemClientSetProperty(client, kIOHIDUserKeyUsageMapKey as CFString, mapping as CFArray) {
            NSLog("Toolbelt: Caps Lock 리매핑 설정 실패")
        }
    }

    // MARK: - macOS 단축키 확인

    /// "이전 입력 소스 선택"(AppleSymbolicHotKeys 60)이 F19로 지정돼 있는지.
    static var isShortcutF19: Bool {
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        guard let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                      "com.apple.symbolichotkeys" as CFString) as? [String: Any],
              let entry = hotkeys["60"] as? [String: Any],
              (entry["enabled"] as? Bool) ?? (entry["enabled"] as? Int == 1),
              let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Int], params.count >= 2 else { return false }
        return params[1] == kVK_F19
    }

    static func openShortcutSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}
