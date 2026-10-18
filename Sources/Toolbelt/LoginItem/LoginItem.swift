import AppKit
import ServiceManagement

/// 로그인 시 자동 실행 (SMAppService.mainApp). 설정의 "로그인 항목"에 Toolbelt로 표시된다.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// 사용자가 설정에서 승인해야 하는 상태 (등록은 됐지만 꺼져 있음)
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if needsApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "로그인 시 자동 실행을 바꾸지 못했습니다"
            alert.informativeText = "\(error.localizedDescription)\n\n시스템 설정 → 일반 → 로그인 항목에서 직접 추가할 수 있습니다."
            alert.addButton(withTitle: "로그인 항목 열기")
            alert.addButton(withTitle: "닫기")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
        }
    }
}
