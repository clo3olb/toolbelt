import AppKit
import ApplicationServices
import CoreAudio

/// 통화 앱이 마이크를 쓰기 시작/중지하는 것을 감지한다 (메뉴바 주황 점과 같은 Core Audio 정보).
/// 2초마다 "지금 마이크를 쓰는 프로세스"를 읽어 대상 앱과 맞춰 본다.
///   시작: 대상 앱이 startDelay 이상 계속 마이크 사용
///   끝:   stopDelay 동안 그 프로세스의 마이크 사용 없음 (카카오톡은 통화를 끊으면 바로 마이크를 놓는다)
///         브라우저는 시작할 때만 창 제목을 보고, 시작한 뒤에는 다른 탭으로 옮겨 제목이 바뀌어도 마이크를 쓰는 동안 계속 통화로 본다.
@MainActor
final class CallDetector {
    struct Call: Equatable {
        let name: String     // 제목에 쓰는 이름 (예: "카카오톡", "Google Meet")
        let processPrefix: String  // 마이크를 쓰는 프로세스 번들 ID 앞부분 — 통화가 이어지는지 이것으로 본다
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
        let now = Date()
        if let current {
            if users.contains(where: { $0.lowercased().hasPrefix(current.processPrefix.lowercased()) }) {
                lastSeen = now
                ending = false
            } else {
                ending = true
                if let lastSeen, now.timeIntervalSince(lastSeen) >= stopDelay {
                    self.current = nil
                    ending = false
                    onCallEnded?(current)
                }
            }
            return
        }

        if let detected = users.lazy.compactMap(CallApps.match).first {
            lastSeen = now
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

    /// 마이크 입력을 쓰고 있는 프로세스 ID (Toolbelt 자신 제외)
    nonisolated static func processIDsUsingMicrophone() -> [pid_t] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return ids.compactMap { id -> pid_t? in
            guard property(id, kAudioProcessPropertyIsRunningInput, UInt32(0)) != 0 else { return nil }
            let pid = property(id, kAudioProcessPropertyPID, pid_t(0))
            return pid > 0 && pid != ownPID ? pid : nil
        }
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
        App(name: "Microsoft Teams", bundlePrefixes: ["com.microsoft.teams", "com.microsoft.teams2"]),
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

    /// 기본 회의 서비스. 설정에서 수정·끄기·삭제할 수 있고 '기본 서비스 복원'으로 되살린다.
    static let defaultMeetingServices: [MeetingService] = [
        MeetingService(name: "Google Meet", keywords: ["Google Meet", "Meet -", "Meet:", "Meet –"]),
        MeetingService(name: "Zoom", keywords: ["Zoom"]),
        MeetingService(name: "Microsoft Teams", keywords: ["Microsoft Teams", "Teams"]),
        MeetingService(name: "Webex", keywords: ["Webex"]),
        MeetingService(name: "Whereby", keywords: ["Whereby"]),
        MeetingService(name: "Jitsi", keywords: ["Jitsi"]),
        MeetingService(name: "Discord", keywords: ["Discord"]),
        MeetingService(name: "Slack", keywords: ["Slack"]),
        MeetingService(name: "Gather", keywords: ["Gather"]),
    ]

    /// 회의 서비스 목록 (위에서부터 먼저 맞는 것). 처음에는 기본 목록 + 예전 '회의 사이트 단어'(callCustomKeywords)를 맨 위로 옮긴다.
    static let meetingServicesKey = "callMeetingServices"
    private static let legacyKeywordsKey = "callCustomKeywords"
    static var meetingServices: [MeetingService] {
        get {
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: meetingServicesKey),
               let services = try? JSONDecoder().decode([MeetingService].self, from: data) {
                return services
            }
            let legacy = (defaults.stringArray(forKey: legacyKeywordsKey) ?? []).map { MeetingService(name: $0, keywords: [$0]) }
            return legacy + defaultMeetingServices
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: meetingServicesKey)
            UserDefaults.standard.removeObject(forKey: legacyKeywordsKey)
        }
    }

    /// 설정에서 켜고 끄는 대상 하나 (통화 앱 또는 브라우저). id는 UserDefaults에 저장하는 키.
    struct Target: Identifiable {
        let id: String
        let name: String
        let isBrowser: Bool
        var isCustom = false
        let bundleIDs: [String]
        var isInstalled: Bool {
            bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        }
    }

    static var targets: [Target] {
        var seen = Set<String>()
        return apps.map { Target(id: $0.name, name: $0.name, isBrowser: false, bundleIDs: $0.bundlePrefixes) }
            + customApps.map { Target(id: $0.bundleID, name: $0.name, isBrowser: false, isCustom: true, bundleIDs: [$0.bundleID]) }
            + browsers.compactMap { browser in
                seen.insert(browser.appBundleID).inserted
                    ? Target(id: browser.appBundleID, name: browser.name, isBrowser: true, bundleIDs: [browser.appBundleID]) : nil
            }
    }

    /// 사용자가 추가한 통화 앱. 번들 ID 앞부분으로 맞추므로 그 앱의 helper(예: kr.example.app.helper)가 마이크를 써도 잡힌다.
    struct CustomApp: Codable, Equatable {
        var name: String
        var bundleID: String
    }

    static let customAppsKey = "callCustomApps"
    static var customApps: [CustomApp] {
        get {
            guard let data = UserDefaults.standard.data(forKey: customAppsKey) else { return [] }
            return (try? JSONDecoder().decode([CustomApp].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: customAppsKey) }
    }

    /// .app 번들 → 추가할 앱 (이미 목록에 있으면 nil)
    static func customApp(at url: URL) -> CustomApp? {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier,
              !targets.contains(where: { $0.bundleIDs.contains { bundleID.lowercased().hasPrefix($0.lowercased()) } }) else { return nil }
        return CustomApp(name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                         bundleID: bundleID)
    }

    /// 지금 마이크를 쓰고 있지만 목록에 없는 앱 (helper 프로세스면 바깥 .app으로 올라가 찾는다)
    static func untrackedAppsUsingMicrophone() -> [CustomApp] {
        var result: [CustomApp] = []
        for pid in CallDetector.processIDsUsingMicrophone() {
            guard let path = NSRunningApplication(processIdentifier: pid)?.bundleURL?.path,
                  let range = path.range(of: ".app") else { continue }
            let outer = URL(fileURLWithPath: String(path[..<range.upperBound]))
            guard outer.path.hasPrefix("/Applications") || outer.path.hasPrefix(NSHomeDirectory() + "/Applications"),
                  let app = customApp(at: outer), !result.contains(app) else { continue }
            result.append(app)
        }
        return result
    }

    /// 자동 녹음에서 끈 대상 id (기본: 모두 켜짐)
    static let disabledTargetsKey = "callDisabledTargets"
    static var disabledTargets: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: disabledTargetsKey) ?? [])
    }

    static func match(processBundleID id: String) -> CallDetector.Call? {
        let lower = id.lowercased()
        let disabled = disabledTargets
        if let app = apps.first(where: { $0.bundlePrefixes.contains { lower.hasPrefix($0.lowercased()) } }) {
            guard !disabled.contains(app.name),
                  let prefix = app.bundlePrefixes.first(where: { lower.hasPrefix($0.lowercased()) }) else { return nil }
            return CallDetector.Call(name: app.name, processPrefix: prefix)
        }
        if let app = customApps.first(where: { lower.hasPrefix($0.bundleID.lowercased()) }) {
            return disabled.contains(app.bundleID) ? nil : CallDetector.Call(name: app.name, processPrefix: app.bundleID)
        }
        for browser in browsers where lower.hasPrefix(browser.processPrefix.lowercased()) && !disabled.contains(browser.appBundleID) {
            if let name = meetingInWindowTitles(of: browser.appBundleID) {
                return CallDetector.Call(name: name, processPrefix: browser.processPrefix)
            }
        }
        return nil
    }

    /// 손쉬운 사용 권한으로 브라우저 창 제목(현재 탭 제목)을 읽어 켜 둔 회의 서비스를 찾는다 (대소문자 무시).
    private static func meetingInWindowTitles(of bundleID: String) -> String? {
        let services = meetingServices.filter { $0.enabled && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        for title in windowTitles(of: bundleID) {
            if let hit = services.first(where: { $0.keywords.contains { title.localizedCaseInsensitiveContains($0) } }) {
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

/// 브라우저 회의 서비스: 창 제목에 keywords 중 하나가 있으면 name으로 녹음한다.
struct MeetingService: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var keywords: [String]
    var enabled = true
}
