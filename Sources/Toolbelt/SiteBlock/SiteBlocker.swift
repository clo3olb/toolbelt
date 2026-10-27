import AppKit

/// 사이트 차단: /etc/hosts에 차단할 도메인을 0.0.0.0으로 적는다 (모든 브라우저·앱에 적용).
///
/// hosts는 root만 고칠 수 있으므로 처음 한 번 관리자 암호로 도우미를 설치한다.
///   /Library/Application Support/Toolbelt/            (root 소유 — 사용자가 스크립트를 바꿀 수 없음)
///   ├── apply-blocklist.sh                            (root 소유, 실행: 목록 → /etc/hosts의 Toolbelt 구역)
///   └── blocked-domains.txt                           (사용자 소유 — 앱이 지금 막을 도메인을 적는다)
///   /Library/LaunchDaemons/kr.clo3olb.toolbelt.siteblock.plist  (목록 파일이 바뀌면·5분마다 스크립트 실행)
/// 스크립트는 도메인 형식만 받아 0.0.0.0/:: 으로만 적으므로, 목록 파일을 누가 고쳐도 사이트를 막는 것 이상은 못 한다.
/// 시간표는 앱이 판단해 목록 파일을 비우거나 채운다 (앱이 꺼져 있으면 마지막 상태가 유지된다).
@MainActor
final class SiteBlocker: ObservableObject {
    static let shared = SiteBlocker()

    enum Mode: String, CaseIterable, Identifiable {
        case off, always, schedule
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: return "끔"
            case .always: return "항상"
            case .schedule: return "시간표"
            }
        }
    }

    static let helperDir = "/Library/Application Support/Toolbelt"
    static let scriptPath = helperDir + "/apply-blocklist.sh"
    static let listPath = helperDir + "/blocked-domains.txt"
    static let daemonLabel = "kr.clo3olb.toolbelt.siteblock"
    static let plistPath = "/Library/LaunchDaemons/\(daemonLabel).plist"
    static let hostsBegin = "# >>> Toolbelt site block"
    static let hostsEnd = "# <<< Toolbelt site block"

    private static let domainsKey = "siteBlockDomains"
    private static let modeKey = "siteBlockMode"
    private static let schedulesKey = "siteBlockSchedules"

    @Published private(set) var domains: [String]
    @Published private(set) var mode: Mode
    @Published var schedules: [BlockSchedule] {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(schedules), forKey: Self.schedulesKey)
            update()
        }
    }
    /// 도우미(스크립트·LaunchDaemon) 설치 여부
    @Published private(set) var helperInstalled = false
    /// 지금 막아야 하는지 (모드·시간표 기준)
    @Published private(set) var isActive = false
    /// /etc/hosts에 실제로 반영됐는지
    @Published private(set) var applied = false
    @Published var errorMessage: String?

    private var timer: Timer?

    private init() {
        let defaults = UserDefaults.standard
        domains = defaults.stringArray(forKey: Self.domainsKey) ?? ["youtube.com", "youtu.be", "instagram.com"]
        mode = Mode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .off
        if let data = defaults.data(forKey: Self.schedulesKey),
           let saved = try? JSONDecoder().decode([BlockSchedule].self, from: data) {
            schedules = saved
        } else {
            schedules = [BlockSchedule(weekdays: [2, 3, 4, 5, 6], start: 9 * 60, end: 18 * 60)]
        }
    }

    func start() {
        update()
        guard timer == nil else { return }
        // 시간표 경계를 놓치지 않도록 30초마다 판단한다
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            Task { @MainActor in SiteBlocker.shared.update() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 설정

    func setMode(_ mode: Mode) {
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        update()
    }

    /// 주소를 붙여 넣어도 도메인만 남긴다 (https://www.youtube.com/watch?v=… → youtube.com). 잘못된 형식이면 false.
    @discardableResult
    func addDomain(_ input: String) -> Bool {
        guard let domain = Self.normalize(input) else { return false }
        if !domains.contains(domain) {
            domains.append(domain)
            saveDomains()
        }
        return true
    }

    func removeDomain(_ domain: String) {
        domains.removeAll { $0 == domain }
        saveDomains()
    }

    private func saveDomains() {
        UserDefaults.standard.set(domains, forKey: Self.domainsKey)
        update()
    }

    static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        text = String(text.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" })
        if text.hasPrefix("www.") { text.removeFirst(4) }
        let label = "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?"
        guard text.range(of: "^\(label)(\\.\(label))+$", options: .regularExpression) != nil else { return nil }
        return text
    }

    // MARK: - 적용

    /// 지금 막아야 할 도메인을 목록 파일에 적고 상태를 갱신한다.
    func update(now: Date = Date()) {
        helperInstalled = FileManager.default.fileExists(atPath: Self.scriptPath)
            && FileManager.default.fileExists(atPath: Self.plistPath)
        switch mode {
        case .off: isActive = false
        case .always: isActive = true
        case .schedule: isActive = schedules.contains { $0.contains(now) }
        }
        let wanted = isActive ? domains : []
        if helperInstalled {
            let content = wanted.map { $0 + "\n" }.joined()
            if (try? String(contentsOfFile: Self.listPath, encoding: .utf8)) != content {
                // 폴더가 root 소유라 바꿔치기(atomic) 대신 그 자리에 쓴다 — LaunchDaemon이 변경을 보고 hosts에 반영
                do {
                    try content.write(toFile: Self.listPath, atomically: false, encoding: .utf8)
                } catch {
                    errorMessage = "차단 목록을 쓰지 못했습니다: \(error.localizedDescription)"
                }
            }
        }
        applied = Self.hostsMatches(wanted)
    }

    /// /etc/hosts의 Toolbelt 구역이 원하는 도메인과 같은지 (모두 읽을 수 있는 파일)
    private static func hostsMatches(_ wanted: [String]) -> Bool {
        guard let hosts = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) else { return false }
        var inBlock = false
        var blocked = Set<String>()
        for line in hosts.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == hostsBegin { inBlock = true; continue }
            if line == hostsEnd { inBlock = false; continue }
            if inBlock, line.hasPrefix("0.0.0.0 ") { blocked.insert(String(line.dropFirst(8))) }
        }
        // 스크립트는 도메인마다 그 자체·www.·m. 세 가지를 적는다
        return blocked == Set(wanted.flatMap { [$0, "www.\($0)", "m.\($0)"] })
    }

    // MARK: - 도우미 설치 / 제거 (관리자 암호)

    func installHelper() {
        errorMessage = nil
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("toolbelt-siteblock-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let script = temp.appendingPathComponent("apply-blocklist.sh")
            let plist = temp.appendingPathComponent("daemon.plist")
            try Self.helperScript.write(to: script, atomically: true, encoding: .utf8)
            try Self.daemonPlist.write(to: plist, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: temp) }
            let dir = Self.shellQuote(Self.helperDir)
            let commands = [
                "mkdir -p \(dir)", "chown root:wheel \(dir)", "chmod 755 \(dir)",
                "install -o root -g wheel -m 755 \(Self.shellQuote(script.path)) \(Self.shellQuote(Self.scriptPath))",
                "touch \(Self.shellQuote(Self.listPath))",
                "chown \(getuid()) \(Self.shellQuote(Self.listPath))", "chmod 644 \(Self.shellQuote(Self.listPath))",
                "install -o root -g wheel -m 644 \(Self.shellQuote(plist.path)) \(Self.shellQuote(Self.plistPath))",
                "launchctl bootout system/\(Self.daemonLabel) 2>/dev/null; true",
                "launchctl bootstrap system \(Self.shellQuote(Self.plistPath))",
            ]
            try Self.runAsAdmin(commands.joined(separator: " && "))
        } catch {
            errorMessage = error.localizedDescription
        }
        update()
    }

    /// 차단 구역을 지우고 도우미를 없앤다
    func uninstallHelper() {
        errorMessage = nil
        let commands = [
            "launchctl bootout system/\(Self.daemonLabel) 2>/dev/null; true",
            ": > \(Self.shellQuote(Self.listPath)) 2>/dev/null; true",
            "[ -f \(Self.shellQuote(Self.scriptPath)) ] && /bin/sh \(Self.shellQuote(Self.scriptPath)); true",
            "rm -f \(Self.shellQuote(Self.plistPath)) \(Self.shellQuote(Self.scriptPath)) \(Self.shellQuote(Self.listPath))",
            "rmdir \(Self.shellQuote(Self.helperDir)) 2>/dev/null; true",
        ]
        do {
            try Self.runAsAdmin(commands.joined(separator: " ; "))
        } catch {
            errorMessage = error.localizedDescription
        }
        update()
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAsAdmin(_ command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with prompt \"Toolbelt 사이트 차단 도우미를 설치하거나 제거합니다.\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -128: 사용자가 취소
            if (error[NSAppleScript.errorNumber] as? Int) == -128 { throw HelperError.cancelled }
            throw HelperError.failed(error[NSAppleScript.errorMessage] as? String ?? "알 수 없는 오류")
        }
    }

    enum HelperError: LocalizedError {
        case cancelled, failed(String)
        var errorDescription: String? {
            switch self {
            case .cancelled: return "취소했습니다."
            case .failed(let message): return "도우미 작업 실패: \(message)"
            }
        }
    }

    // MARK: - 도우미 파일 내용

    /// root로 실행된다. 도메인 형식만 받아 0.0.0.0 / :: 으로만 적는다. TOOLBELT_HOSTS는 시험용.
    static let helperScript = """
    #!/bin/sh
    # Toolbelt 사이트 차단: blocked-domains.txt의 도메인을 /etc/hosts의 Toolbelt 구역에 적는다.
    LIST="\(listPath)"
    HOSTS="${TOOLBELT_HOSTS:-/etc/hosts}"
    BEGIN="\(hostsBegin)"
    END="\(hostsEnd)"
    TMP=$(mktemp /tmp/toolbelt-hosts.XXXXXX) || exit 1
    awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$HOSTS" > "$TMP"
    if [ -f "$LIST" ]; then
      DOMAINS=$(tr 'A-Z' 'a-z' < "$LIST" | grep -E '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' | head -n 500 | sort -u)
      if [ -n "$DOMAINS" ]; then
        {
          echo "$BEGIN"
          for d in $DOMAINS; do
            for h in "$d" "www.$d" "m.$d"; do echo "0.0.0.0 $h"; echo ":: $h"; done
          done
          echo "$END"
        } >> "$TMP"
      fi
    fi
    if ! cmp -s "$TMP" "$HOSTS"; then
      cat "$TMP" > "$HOSTS"
      dscacheutil -flushcache 2>/dev/null
      killall -HUP mDNSResponder 2>/dev/null
    fi
    rm -f "$TMP"
    exit 0

    """

    static let daemonPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key><string>\(daemonLabel)</string>
        <key>ProgramArguments</key>
        <array><string>/bin/sh</string><string>\(scriptPath)</string></array>
        <key>WatchPaths</key>
        <array><string>\(listPath)</string></array>
        <key>RunAtLoad</key><true/>
        <key>StartInterval</key><integer>300</integer>
    </dict>
    </plist>

    """
}

/// 차단 시간대. weekdays는 Calendar 기준 (1 = 일요일 … 7 = 토요일), start/end는 0시부터 분.
/// start > end면 자정을 넘긴다 (예: 22:00–02:00, 시작한 요일 기준). start == end면 그 요일 하루 종일.
struct BlockSchedule: Codable, Identifiable, Equatable {
    var id = UUID()
    var weekdays: Set<Int>
    var start: Int
    var end: Int

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let previous = weekday == 1 ? 7 : weekday - 1
        if start == end { return weekdays.contains(weekday) }
        if start < end { return weekdays.contains(weekday) && minute >= start && minute < end }
        return (weekdays.contains(weekday) && minute >= start) || (weekdays.contains(previous) && minute < end)
    }
}
