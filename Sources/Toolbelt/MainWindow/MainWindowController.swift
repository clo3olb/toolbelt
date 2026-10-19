import AppKit
import SwiftUI

/// 메인 창의 페이지: 기능별 상세 화면 + 설정
enum MainPage: Hashable {
    case feature(FeatureID)
    case settings

    static let recording = MainPage.feature(.recording)
}

@MainActor
final class MainWindowState: ObservableObject {
    @Published var page: MainPage = .recording
    let recordings = RecordingsBrowserState()
    let model = PanelModel()
}

/// 팝오버보다 자세한 기능 화면과 설정을 담는 창.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private let state = MainWindowState()

    private override init() {
        super.init()
        // 창이 앞에 있으므로 창 배치는 Toolbelt 직전에 쓰던 앱의 창에 적용한다
        state.model.runInPreviousApp = { work in LastAppTracker.shared.runInLastApp(work) }
    }

    func show(_ page: MainPage? = nil, selectRecording id: String? = nil) {
        RecordingController.shared.reload()
        state.model.refreshAll()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Toolbelt"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 820, height: 480)
            window.contentView = NSHostingView(rootView: MainWindowView(state: state))
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("MainWindow")
            self.window = window
        }
        if let page { state.page = page }
        if let id {
            state.page = .recording
            state.recordings.selectedID = id
        }
        state.model.startUpdating()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        state.recordings.player.stop()
        state.model.stopUpdating()
    }
}

// MARK: - 화면

private struct MainWindowView: View {
    @ObservedObject var state: MainWindowState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.page) {
                Section("기능") {
                    ForEach(FeatureID.allCases) { feature in
                        Label(feature.title, systemImage: feature.symbol).tag(MainPage.feature(feature))
                    }
                }
                Section {
                    Label("설정", systemImage: "gearshape").tag(MainPage.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch state.page {
            case .feature(.recording):
                RecordingsBrowser(controller: .shared, state: state.recordings)
            case .feature(.clipboard):
                ClipboardBrowser(history: .shared)
            case .feature(.system):
                SystemPage(model: state.model)
            case .feature(.storage):
                StoragePage(model: state.model)
            case .feature(.windowSnap):
                WindowSnapPage(model: state.model)
            case .feature(.display):
                DisplayPage(model: state.model)
            case .feature(.keyboard):
                KeyboardPage(model: state.model)
            case .settings:
                SettingsPage(model: state.model, layout: .shared, recorder: .shared)
            }
        }
        // 페이지를 옮길 때 디스플레이·권한 상태 등을 새로 읽는다
        .onChange(of: state.page) { _, _ in state.model.refreshAll() }
    }
}
