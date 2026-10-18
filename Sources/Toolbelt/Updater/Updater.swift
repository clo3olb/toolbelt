import AppKit
import Combine
import Sparkle

/// Sparkle 자동 업데이트. Info.plist의 SUFeedURL(GitHub Releases의 appcast.xml)을 하루 한 번 확인하고,
/// 새 버전이 있으면 받아서(EdDSA 서명 확인) 바꾼 뒤 다시 실행한다.
@MainActor
final class Updater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    @Published private(set) var canCheck = false
    @Published private(set) var automaticallyChecks = true

    private var controller: SPUStandardUpdaterController!
    private var observer: AnyCancellable?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        observer = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ on: Bool) {
        controller.updater.automaticallyChecksForUpdates = on
        automaticallyChecks = on
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Dock 아이콘이 없는 메뉴바 앱이라, 예약 확인에서 찾은 업데이트 창을 앞으로 띄워야 보인다
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        DispatchQueue.main.async { NSApp.activate() }
    }
}
