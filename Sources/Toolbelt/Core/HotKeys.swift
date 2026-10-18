import Foundation
import Carbon.HIToolbox

struct HotKey: Codable, Equatable, Hashable {
    let keyCode: UInt32
    /// Carbon 수정자 (controlKey | optionKey | shiftKey | cmdKey)
    let modifiers: UInt32

    static let controlOption = UInt32(controlKey | optionKey)
    static let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)

    /// "⌃⌥←" 같은 표시
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + HotKey.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Return: return "↩"
        case kVK_ANSI_KeypadEnter: return "⌅"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Grave: return "`"
        default: break
        }
        let fKeys: [Int: Int] = [kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7,
                                 kVK_F8: 8, kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12, kVK_F13: 13,
                                 kVK_F14: 14, kVK_F15: 15, kVK_F16: 16, kVK_F17: 17, kVK_F18: 18, kVK_F19: 19, kVK_F20: 20]
        if let n = fKeys[Int(code)] { return "F\(n)" }
        return letterOrDigit(code) ?? "#\(code)"
    }

    /// 현재 키보드 배열 기준 글자 (영문 자판 위치)
    private static func letterOrDigit(_ code: UInt32) -> String? {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        ]
        return map[Int(code)]
    }
}

/// 메뉴 항목과 (선택적) 전역 단축키를 공유하는 실행 단위.
struct Command {
    let title: String
    let hotKey: HotKey?
    let run: () -> Void
}

/// Carbon RegisterEventHotKey 기반 전역 단축키. 손쉬운 사용 권한 없이도 키 입력은 받는다.
/// group으로 묶어 두면 설정이 바뀔 때 그 묶음만 해제하고 다시 등록할 수 있다.
enum HotKeyCenter {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var groups: [String: [UInt32]] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    /// 항상 유지하는 단축키 (예: ⌃⌥⌘R 비상 복구)
    static func register(_ commands: [Command]) {
        _ = add(commands)
    }

    /// 묶음을 통째로 바꾼다 (기존 묶음 해제 후 등록)
    static func replaceGroup(_ name: String, with commands: [Command]) {
        removeGroup(name)
        groups[name] = add(commands)
    }

    static func removeGroup(_ name: String) {
        for id in groups.removeValue(forKey: name) ?? [] {
            if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
            handlers[id] = nil
        }
    }

    private static func add(_ commands: [Command]) -> [UInt32] {
        installHandlerIfNeeded()
        var ids: [UInt32] = []
        for command in commands {
            guard let hotKey = command.hotKey else { continue }
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x54424C54) /* 'TBLT' */, id: id)
            let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                NSLog("Toolbelt: \(hotKey.display) 등록 실패 (\(status)) — 다른 앱이 사용 중일 수 있음")
                continue
            }
            handlers[id] = command.run
            refs[id] = ref
            ids.append(id)
        }
        return ids
    }

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKeyCenter.handlers[id.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
