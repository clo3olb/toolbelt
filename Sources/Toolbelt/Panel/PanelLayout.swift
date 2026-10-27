import AppKit

/// 기능 단위. 팝오버 섹션이자 메인 창 사이드바 항목이다.
enum FeatureID: String, CaseIterable, Identifiable, Codable {
    case recording, clipboard, siteBlock, system, storage, windowSnap, display, keyboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: return "녹음"
        case .clipboard: return "클립보드"
        case .siteBlock: return "사이트 차단"
        case .system: return "시스템"
        case .storage: return "저장 장치"
        case .windowSnap: return "창 배치"
        case .display: return "디스플레이"
        case .keyboard: return "키보드"
        }
    }

    var symbol: String {
        switch self {
        case .recording: return "waveform"
        case .clipboard: return "doc.on.clipboard"
        case .siteBlock: return "hand.raised"
        case .system: return "gauge.with.dots.needle.67percent"
        case .storage: return "externaldrive"
        case .windowSnap: return "rectangle.split.2x1"
        case .display: return "display.2"
        case .keyboard: return "keyboard"
        }
    }
}

/// 팝오버에 어떤 기능을 어떤 순서로 보여줄지 (설정 페이지에서 바꾼다).
@MainActor
final class PanelLayout: ObservableObject {
    static let shared = PanelLayout()

    private static let orderKey = "panelOrder"
    private static let hiddenKey = "panelHidden"

    /// 모든 기능의 순서 (숨긴 것 포함)
    @Published private(set) var order: [FeatureID]
    @Published private(set) var hidden: Set<FeatureID>

    var visible: [FeatureID] { order.filter { !hidden.contains($0) } }

    private init() {
        let defaults = UserDefaults.standard
        var order = (defaults.stringArray(forKey: Self.orderKey) ?? []).compactMap(FeatureID.init(rawValue:))
        // 새로 추가된 기능은 뒤에 붙인다
        order += FeatureID.allCases.filter { !order.contains($0) }
        self.order = order
        hidden = Set((defaults.stringArray(forKey: Self.hiddenKey) ?? []).compactMap(FeatureID.init(rawValue:)))
    }

    func isVisible(_ id: FeatureID) -> Bool { !hidden.contains(id) }

    func setVisible(_ id: FeatureID, _ visible: Bool) {
        if visible { hidden.remove(id) } else { hidden.insert(id) }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func reset() {
        order = FeatureID.allCases
        hidden = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: Self.orderKey)
        UserDefaults.standard.set(hidden.map(\.rawValue), forKey: Self.hiddenKey)
    }
}

/// Toolbelt가 아닌, 마지막으로 앞에 있던 앱. 메인 창의 창 배치 버튼은 이 앱의 창에 적용한다.
@MainActor
final class LastAppTracker {
    static let shared = LastAppTracker()
    private(set) var app: NSRunningApplication?
    private var observer: NSObjectProtocol?

    func start() {
        app = NSWorkspace.shared.frontmostApplication.flatMap { isSelf($0) ? nil : $0 }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self, !self.isSelf(app) else { return }
                self.app = app
            }
        }
    }

    /// 그 앱을 앞으로 가져온 뒤 실행
    func runInLastApp(_ work: @escaping () -> Void) {
        app?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func isSelf(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }
}
