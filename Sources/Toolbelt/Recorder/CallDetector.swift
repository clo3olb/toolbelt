import AppKit
import ApplicationServices
import CoreAudio

/// 통화 앱이 마이크를 쓰기 시작/중지하는 것을 감지한다 (메뉴바 주황 점과 같은 Core Audio 정보).
/// 2초마다 "지금 마이크를 쓰는 프로세스"를 읽어 대상 앱과 맞춰 본다.
///   시작: 대상 앱이 startDelay 이상 계속 마이크 사용
///   끝:   stopDelay 동안 대상 앱의 마이크 사용 없음 (카카오톡은 통화를 끊으면 바로 마이크를 놓는다)
@MainActor
final class CallDetector {
    struct Call: Equatable {
        let name: String     // 제목에 쓰는 이름 (예: "카카오톡", "Google Meet")
    }

    var onCallStarted: ((Call) -> Void)?
    var onCallEnded: ((Call) -> Void)?
    /// 통화 중 마이크 사용이 끊겨 정지 대기 중인지 (true) / 다시 쓰기 시작했는지 (false)
    var onCallEnding: ((Bool) -> Void)?
    private(set) var current: Call?

    private let startDelay: TimeInterval = 3
    private let stopDelay: TimeInterval = 5
    private var timer: Timer?
    private var candidate: (call: Call, since: Date)?
    private var lastSeen: Date?
    private var lastLoggedUsers: [String] = []
    private var ending = false {
        didSet { if ending != oldValue { onCallEnding?(ending) } }
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        candidate = nil
        if let current {
            self.current = nil
            onCallEnded?(current)
        }
    }

    private func poll() {
        let users = Self.processesUsingMicrophone()
        if users != lastLoggedUsers {
            // 새 앱을 대상에 추가할 때 실제 번들 ID를 확인하기 위한 로그 (log show --predicate 'process == "Toolbelt"')
            NSLog("Toolbelt: 마이크 사용 중인 프로세스: \(users.isEmpty ? "없음" : users.joined(separator: ", "))")
            lastLoggedUsers = users
        }
        let detected = users.lazy.compactMap(CallApps.match).first
        let now = Date()

        if let detected {
            lastSeen = now
            ending = false
            guard current == nil else { return }
            if let candidate, candidate.call == detected {
                if now.timeIntervalSince(candidate.since) >= startDelay {
                    current = detected
                    self.candidate = nil
                    onCallStarted?(detected)
                }
            } else {
                candidate = (detected, now)
            }
        } else {
            candidate = nil
            guard let current else { return }
            ending = true
            if let lastSeen, now.timeIntervalSince(lastSeen) >= stopDelay {
                self.current = nil
                ending = false
                onCallEnded?(current)
            }
        }
    }

    /// 마이크 입력을 쓰고 있는 프로세스들의 번들 ID (Toolbelt 자신 제외)
    nonisolated static func processesUsingMicrophone() -> [String] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return ids.compactMap { id -> String? in
            guard property(id, kAudioProcessPropertyIsRunningInput, UInt32(0)) != 0,
                  property(id, kAudioProcessPropertyPID, pid_t(0)) != ownPID else { return nil }
            let bundle = property(id, kAudioProcessPropertyBundleID, "" as CFString) as String
            return bundle.isEmpty ? nil : bundle
        }
        .sorted()
    }

    nonisolated private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ fallback: T) -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return fallback }
        return value
    }
}

/// 자동 녹음 대상. 마이크를 쓰는 프로세스의 번들 ID를 앞부분으로 맞춘다 (Chrome·Slack 등은 helper 프로세스가 마이크를 쓴다).
enum CallApps {
    private struct App {
        let name: String
        let bundlePrefixes: [String]
    }

    private static let apps: [App] = [
        App(name: "전화", bundlePrefixes: ["com.apple.mobilephone"]),
        App(name: "FaceTime", bundlePrefixes: ["com.apple.FaceTime"]),
        App(name: "Slack", bundlePrefixes: ["com.tinyspeck.slackmacgap"]),
        App(name: "카카오톡", bundlePrefixes: ["com.kakao.KakaoTalkMac"]),
        App(name: "WhatsApp", bundlePrefixes: ["net.whatsapp.WhatsApp"]),
        App(name: "Zoom", bundlePrefixes: ["us.zoom.xos"]),
        App(name: "Microsoft Teams", bundlePrefixes: ["com.microsoft.teams"]),
        App(name: "Discord", bundlePrefixes: ["com.hnc.Discord"]),
        App(name: "Webex", bundlePrefixes: ["Cisco-Systems.Spark"]),
    ]

    /// 브라우저: 마이크를 쓰는 프로세스 → 창 제목을 읽을 앱. 창 제목에 회의 서비스 이름이 있을 때만 통화로 본다.
    /// Safari 계열은 WebKit GPU 프로세스가 마이크를 쓴다.
    private static let browsers: [(processPrefix: String, appBundleID: String, name: String)] = [
        ("com.google.Chrome", "com.google.Chrome", "Chrome"),
        ("company.thebrowser", "company.thebrowser.Browser", "Arc"),
        ("com.apple.Safari", "com.apple.Safari", "Safari"),
        ("com.apple.WebKit.GPU", "com.apple.Safari", "Safari"),
        ("com.microsoft.edgemac", "com.microsoft.edgemac", "Edge"),
        ("com.naver.Whale", "com.naver.Whale", "Whale"),
    ]

    /// 창 제목 키워드 → 제목에 쓸 서비스 이름 (앞에서부터 먼저 맞는 것)
    private static let meetingKeywords: [(keyword: String, name: String)] = [
        ("Google Meet", "Google Meet"), ("Meet -", "Google Meet"), ("Meet:", "Google Meet"), ("Meet –", "Google Meet"),
        ("Zoom", "Zoom"), ("Microsoft Teams", "Microsoft Teams"), ("Teams", "Microsoft Teams"),
        ("Webex", "Webex"), ("Whereby", "Whereby"), ("Jitsi", "Jitsi"), ("Discord", "Discord"),
        ("Slack", "Slack"), ("Gather", "Gather"),
    ]

    /// 사용자가 설정에서 추가한 회의 사이트 단어 (창 제목에 이 단어가 있으면 통화로 본다, 대소문자 무시)
    static let customKeywordsKey = "callCustomKeywords"
    static var customKeywords: [String] {
        UserDefaults.standard.stringArray(forKey: customKeywordsKey) ?? []
    }

    static func match(processBundleID id: String) -> CallDetector.Call? {
        let lower = id.lowercased()
        if let app = apps.first(where: { $0.bundlePrefixes.contains { lower.hasPrefix($0.lowercased()) } }) {
            return CallDetector.Call(name: app.name)
        }
        for browser in browsers where lower.hasPrefix(browser.processPrefix.lowercased()) {
            if let name = meetingInWindowTitles(of: browser.appBundleID) {
                return CallDetector.Call(name: name)
            }
        }
        return nil
    }

    /// 손쉬운 사용 권한으로 브라우저 창 제목(현재 탭 제목)을 읽어 회의 서비스를 찾는다. 사용자 단어를 먼저 본다.
    private static func meetingInWindowTitles(of bundleID: String) -> String? {
        let custom = customKeywords
        for title in windowTitles(of: bundleID) {
            if let hit = custom.first(where: { title.localizedCaseInsensitiveContains($0) }) { return hit }
            if let hit = meetingKeywords.first(where: { title.localizedCaseInsensitiveContains($0.keyword) }) {
                return hit.name
            }
        }
        return nil
    }

    static func windowTitles(of bundleID: String) -> [String] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).flatMap { app -> [String] in
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { return [] }
            return windows.compactMap { window in
                var title: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
                      let title = title as? String, !title.isEmpty else { return nil }
                return title
            }
        }
    }

    /// 지금 마이크를 쓰는 브라우저와 그 창 제목들 (설정에서 어떤 단어를 넣을지 보여주기 위함)
    static func browsersUsingMicrophone() -> [(browser: String, titles: [String])] {
        let users = CallDetector.processesUsingMicrophone().map { $0.lowercased() }
        var seen = Set<String>()
        return browsers.compactMap { browser in
            guard users.contains(where: { $0.hasPrefix(browser.processPrefix.lowercased()) }),
                  seen.insert(browser.appBundleID).inserted else { return nil }
            return (browser.name, windowTitles(of: browser.appBundleID))
        }
    }
}
