import AppKit
import Combine
import SwiftUI

/// 메뉴바 아이콘 클릭 → SwiftUI 팝오버.
@MainActor
final class PanelController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model = PanelModel()
    /// 팝오버를 열기 직전에 앞에 있던 앱. 창 배치는 이 앱의 창에 적용한다.
    private var previousApp: NSRunningApplication?
    private var recordingObserver: AnyCancellable?

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()

        let host = NSHostingController(rootView: PanelView(model: model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        model.dismiss = { [weak self] in self?.popover.performClose(nil) }
        model.runInPreviousApp = { [weak self] work in self?.runInPreviousApp(work) }

        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        // 녹음 중에는 빨간 녹음 표시, 통화 종료를 감지해 곧 자동 정지할 때는 주황 빈 원
        let recorder = RecordingController.shared
        recordingObserver = recorder.$isRecording
            .combineLatest(recorder.$autoCallEnding)
            .receive(on: RunLoop.main)
            .sink { [weak self] recording, ending in self?.updateIcon(recording: recording, ending: ending) }
    }

    private func updateIcon(recording: Bool, ending: Bool) {
        guard let button = statusItem.button else { return }
        if recording && ending {
            let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Toolbelt 통화 종료 감지, 곧 녹음 정지")
            image?.isTemplate = false
            button.image = image?.withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
        } else if recording {
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Toolbelt 녹음 중")
            image?.isTemplate = false
            button.image = image?.withSymbolConfiguration(.init(paletteColors: [.white, .systemRed]))
        } else {
            button.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "Toolbelt")
        }
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        model.refreshAll()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // 키보드(⌘Q, esc)가 팝오버로 가도록
        popover.contentViewController?.view.window?.makeKey()
    }

    private func runInPreviousApp(_ work: @escaping () -> Void) {
        popover.performClose(nil)
        previousApp?.activate(options: [])
        // 포커스가 원래 앱으로 돌아간 뒤 실행
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) { model.startUpdating() }
    func popoverDidClose(_ notification: Notification) { model.stopUpdating() }
}
