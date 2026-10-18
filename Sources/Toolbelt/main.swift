import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "Toolbelt")
        panel = PanelController(statusItem: statusItem)
        installMainMenu()
        LastAppTracker.shared.start()

        HotKeyCenter.register([DisplayCommands.reconnectAll])
        WindowSnapSettings.shared.applyHotKeys()
        CapsLockSwitch.start()
        RecordingController.shared.startServices()
        // 처음 설치한 사용자에게는 시작 안내(권한·선택 기능)를, 기존 사용자에게는 손쉬운 사용 권한 요청만
        if OnboardingWindowController.shared.shouldShowOnLaunch {
            OnboardingWindowController.shared.show()
        } else if !AXIsProcessTrusted() {
            Permissions.prompt()
        }
    }

    /// 메뉴바가 보이지 않는 앱이지만, 녹음 창에서 ⌘C·⌘A·⌘W 같은 키가 동작하도록 기본 메뉴를 둔다.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appItem.submenu?.addItem(settings)
        appItem.submenu?.addItem(.separator())
        appItem.submenu?.addItem(withTitle: "Toolbelt 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "윈도우")
        window.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @MainActor @objc private func openSettings() {
        MainWindowController.shared.show(.settings)
    }

    /// 녹음 중이면 파일을 마무리한 뒤 종료한다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard RecordingController.shared.isRecording else { return .terminateNow }
        Task { @MainActor in
            await RecordingController.shared.finishForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Caps Lock 리매핑은 시스템 전체에 걸리므로 종료할 때 원래대로 돌려놓는다
        CapsLockSwitch.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
