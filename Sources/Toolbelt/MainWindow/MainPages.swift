import AVFoundation
import SwiftUI

/// 메인 창 페이지 공통 틀: 큰 제목 + 스크롤 내용
struct PageScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.largeTitle.weight(.bold))
                    if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
                }
                content()
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 제목이 있는 카드
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - 시스템

struct SystemPage: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        PageScaffold(title: "시스템", subtitle: "창이 열려 있는 동안 2초마다 갱신합니다.") {
            Card(title: "사용량") {
                HStack(alignment: .top, spacing: 12) {
                    RingGauge(title: "CPU", usage: model.cpu, tint: .blue)
                    RingGauge(title: "메모리", usage: model.memory, tint: .green)
                    RingGauge(title: "저장 공간", usage: model.storage, tint: .purple)
                }
                .padding(.vertical, 6)
            }
            Card(title: "기준") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• CPU: 전체 코어 평균 사용률")
                    Text("• 메모리: 활성 상태 보기의 \"사용된 메모리\"와 같은 기준 (앱 메모리 + 와이어드 + 압축됨)")
                    Text("• 저장 공간: 시동 디스크, Finder와 같은 기준 (정리 가능한 공간은 남은 공간으로 계산)")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            Button("활성 상태 보기 열기", systemImage: "chart.bar.xaxis", action: model.openActivityMonitor)
        }
    }
}

// MARK: - 클립보드

struct ClipboardPage: View {
    @ObservedObject var history: ClipboardHistory
    @State private var search = ""
    @State private var confirmClear = false

    private var filtered: [ClipItem] {
        guard !search.isEmpty else { return history.items }
        return history.items.filter { ($0.text ?? $0.preview).localizedCaseInsensitiveContains(search)
            || ($0.source ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        PageScaffold(title: "클립보드", subtitle: "복사한 텍스트를 최근 \(ClipboardHistory.maxItems)개, 7일 동안 이 Mac에만 암호화해 보관합니다.") {
            Card(title: "기록") {
                Toggle("클립보드 기록", isOn: Binding(get: { history.isEnabled }, set: history.setEnabled)).toggleStyle(.switch)
                if history.isEnabled {
                    Toggle("일시정지 (이동안 복사한 것은 기록하지 않음)", isOn: Binding(get: { history.isPaused }, set: history.setPaused))
                        .toggleStyle(.switch)
                }
                accessStatus
                Text("API 키·토큰·개인 키, 비밀번호 관리자에서 복사한 값, 제외 앱에서 복사한 값은 **비밀**로 저장합니다: 값은 키체인에만 두고 기록에는 가려서 보여주며, 다시 복사할 때 Touch ID나 Mac 암호를 확인하고 \(Int(ClipboardHistory.secretClearDelay))초 뒤 클립보드에서 지웁니다.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "기록 \(history.items.count)개") {
                HStack {
                    TextField("검색", text: $search).textFieldStyle(.roundedBorder)
                    Button("모두 지우기") { confirmClear = true }.disabled(history.items.isEmpty)
                        .confirmationDialog("클립보드 기록과 비밀 항목을 모두 지울까요? (비밀로 기억한 값은 남습니다)", isPresented: $confirmClear) {
                            Button("모두 지우기", role: .destructive, action: history.clearAll)
                        }
                }
                if let notice = history.notice {
                    Text(notice).font(.caption.weight(.medium)).foregroundStyle(.red)
                }
                VStack(spacing: 0) {
                    ForEach(filtered) { item in
                        ClipRow(item: item, history: history)
                        Divider().opacity(0.4)
                    }
                }
                if filtered.isEmpty {
                    Text(history.items.isEmpty ? "아직 기록이 없습니다" : "검색 결과가 없습니다").foregroundStyle(.secondary)
                }
                Text("일반 항목에 비밀번호가 들어갔다면 🔒 버튼으로 비밀로 바꾸세요. 같은 값을 다시 복사하면 처음부터 비밀로 저장합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("비밀로 기억한 값 \(history.rememberedSecrets.count)개").font(.callout)
                    Text("(값은 저장하지 않고 되돌릴 수 없는 지문만 보관)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("모두 잊기", action: history.forgetRememberedSecrets).controlSize(.small)
                        .disabled(history.rememberedSecrets.isEmpty)
                }
            }

            Card(title: "비밀로 취급할 앱") {
                Text("이 앱들에서 복사한 값은 모두 비밀로 저장합니다.").font(.callout).foregroundStyle(.secondary)
                ForEach(history.excludedApps, id: \.self) { bundleID in
                    HStack {
                        Text(appName(bundleID))
                        Text(isInstalled(bundleID) ? bundleID : "설치 안 됨").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Button { history.removeExcludedApp(bundleID) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Menu("실행 중인 앱 추가") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            if let id = app.bundleIdentifier { history.addExcludedApp(id) }
                        }
                    }
                }
                .fixedSize()
            }
        }
        .onAppear(perform: history.refreshAccess)
    }

    @ViewBuilder
    private var accessStatus: some View {
        let (ok, text): (Bool, String) = switch history.accessBehavior {
        case .alwaysAllow: (true, "클립보드 접근: 항상 허용")
        case .alwaysDeny: (false, "클립보드 접근이 거부돼 기록할 수 없습니다. 시스템 설정에서 '항상 허용'으로 바꾸세요.")
        case .ask: (false, "복사할 때마다 macOS가 허용을 물을 수 있습니다. 시스템 설정에서 '항상 허용'으로 바꾸세요.")
        default: (false, "처음 기록할 때 macOS가 클립보드 접근 허용을 묻습니다. '허용'을 눌러 주세요.")
        }
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(ok ? .green : .orange)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if !ok {
                Button(history.accessBehavior == .default ? "허용하기" : "설정 열기", action: history.requestAccess)
                    .controlSize(.small)
            }
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && !history.excludedApps.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return ClipboardHistory.knownAppNames[bundleID] ?? bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

// MARK: - 저장 장치

struct StoragePage: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        PageScaffold(title: "저장 장치", subtitle: "연결된 디스크의 용량입니다. 꽂거나 뽑으면 바로 갱신됩니다.") {
            ForEach(model.volumes) { volume in
                Card(title: volume.isRoot ? "시동 디스크" : volume.isInternal ? "내장 디스크" : "외장 디스크") {
                    VolumeRow(volume: volume, model: model, showMenu: false)
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                        GridRow { Text("포맷").foregroundStyle(.secondary); Text(volume.format) }
                        GridRow { Text("위치").foregroundStyle(.secondary); Text(volume.url.path).font(.callout.monospaced()) }
                    }
                    .font(.callout)
                    HStack {
                        Button("Finder에서 열기") { model.reveal(volume) }
                        if volume.isEjectable { Button("꺼내기") { model.eject(volume) } }
                    }
                    .controlSize(.small)
                }
            }
            if model.volumes.isEmpty {
                Text("연결된 디스크가 없습니다").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 창 배치

struct WindowSnapPage: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var settings = WindowSnapSettings.shared
    @State private var notice: String?

    var body: some View {
        PageScaffold(title: "창 배치", subtitle: "쓸 배치를 켜고 단축키를 지정합니다. 켠 배치는 팝오버에도 나타납니다.") {
            if !model.trusted { PermissionBanner(model: model) }
            HStack {
                Text("단축키 칸을 클릭하고 키를 누르면 지정됩니다 (⌫ 지우기, ⎋ 취소). 아이콘을 누르면 Toolbelt 직전에 쓰던 앱의 창에 바로 적용합니다.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("기본값으로") { settings.resetToDefaults(); notice = nil }.controlSize(.small)
            }
            if let notice {
                Label(notice, systemImage: "info.circle").font(.callout).foregroundStyle(.orange)
            }
            ForEach(SnapAction.Category.allCases, id: \.self) { category in
                Card(title: category.rawValue) {
                    VStack(spacing: 2) {
                        ForEach(SnapAction.allCases.filter { $0.category == category }) { action in
                            SnapActionRow(action: action, model: model, settings: settings) { notice = $0 }
                        }
                    }
                    if category == .halves {
                        Text("이미 오른쪽 절반에 붙은 창에서 오른쪽 절반을 한 번 더 하면 오른쪽 모니터의 왼쪽 절반으로 넘어갑니다 (왼쪽은 반대).")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }
            }
        }
    }
}

private struct SnapActionRow: View {
    let action: SnapAction
    @ObservedObject var model: PanelModel
    @ObservedObject var settings: WindowSnapSettings
    let report: (String?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { model.snap(action) } label: { SnapGlyph(action: action, size: 26) }
                .buttonStyle(.plain).disabled(!model.trusted).help("지금 적용")
            Text(action.title)
                .foregroundStyle(settings.isEnabled(action) ? Color.primary : Color.secondary)
            Spacer()
            ShortcutField(hotKey: settings.hotKeys[action]) { report(settings.setHotKey($0, for: action)) }
                .disabled(!settings.isEnabled(action))
            Toggle("", isOn: Binding(get: { settings.isEnabled(action) }, set: { settings.setEnabled(action, $0) }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 디스플레이

struct DisplayPage: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        PageScaffold(title: "디스플레이", subtitle: "케이블을 꽂은 채 모니터를 macOS에서 뺀 것처럼 연결 해제할 수 있습니다.") {
            Card(title: "모니터") {
                VStack(spacing: 10) {
                    ForEach(model.displays, id: \.id) { display in
                        DisplayRow(display: display, canDisconnect: model.activeDisplayCount > 1, model: model)
                    }
                }
                if model.hasDisabledDisplays {
                    Button("모두 다시 연결  ⌃⌥⌘R") { model.displayAction(DisplayCommands.reconnectAll.run) }
                        .padding(.top, 4)
                }
            }
            Card(title: "안전장치") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 마지막 남은 디스플레이는 연결 해제할 수 없습니다.")
                    Text("• 연결 해제 후 15초 안에 \"유지\"를 누르지 않으면 자동으로 다시 연결합니다.")
                    Text("• 연결 해제는 로그아웃하거나 재부팅하면 원래대로 돌아옵니다.")
                    Text("• 화면이 안 보이면 ⌃⌥⌘R로 모든 디스플레이를 다시 연결합니다.")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 키보드

struct KeyboardPage: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        PageScaffold(title: "키보드") {
            Card(title: "한/영 전환") {
                CapsLockControl(model: model)
                Text("Caps Lock을 F19로 바꾸고, macOS '이전 입력 소스 선택' 단축키(F19)로 전환합니다. 길게 누르기 판정이 없어 누르는 즉시 바뀝니다. 대문자 고정은 쓰지 않습니다.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: model.capsShortcutReady ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(model.capsShortcutReady ? .green : .secondary)
                    Text(model.capsShortcutReady ? "'이전 입력 소스 선택' 단축키가 F19로 지정돼 있습니다." : "'이전 입력 소스 선택' 단축키가 F19가 아닙니다.")
                        .font(.callout)
                    Spacer()
                    Button("키보드 설정 열기", action: model.openShortcutSettings).controlSize(.small)
                }
            }
        }
    }
}

// MARK: - 설정

struct SettingsPage: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var layout: PanelLayout
    @ObservedObject var recorder: RecordingController

    var body: some View {
        PageScaffold(title: "설정") {
            Card(title: "팝오버") {
                Text("메뉴바 아이콘을 눌렀을 때 보일 기능을 고르고, 끌어서 순서를 바꿉니다.")
                    .font(.callout).foregroundStyle(.secondary)
                List {
                    ForEach(layout.order) { feature in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Image(systemName: feature.symbol).frame(width: 22)
                            Text(feature.title)
                            Spacer()
                            Toggle("", isOn: Binding(get: { layout.isVisible(feature) },
                                                     set: { layout.setVisible(feature, $0) }))
                                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        }
                        .padding(.vertical, 3)
                    }
                    .onMove(perform: layout.move)
                }
                .frame(height: CGFloat(layout.order.count) * 38 + 12)
                .scrollDisabled(true)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("기본값으로", action: layout.reset).controlSize(.small)
            }

            Card(title: "일반") {
                Toggle(isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled)) {
                    Text(model.loginNeedsApproval ? "로그인 시 자동 실행 (설정에서 승인 필요)" : "로그인 시 자동 실행")
                }
                .toggleStyle(.switch)
                Button("시작 안내 다시 보기") { OnboardingWindowController.shared.show() }.controlSize(.small)
            }

            UpdateCard(updater: .shared)

            Card(title: "녹음") {
                Toggle("통화 자동 녹음", isOn: Binding(get: { recorder.autoRecordCalls }, set: recorder.setAutoRecordCalls))
                    .toggleStyle(.switch)
                HStack {
                    Text(RecordingStore.root.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Finder에서 열기") {
                        try? FileManager.default.createDirectory(at: RecordingStore.root, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(RecordingStore.root)
                    }
                    .controlSize(.small)
                }
            }

            Card(title: "권한") {
                PermissionRow(title: "손쉬운 사용", detail: "창 배치, 브라우저 회의 감지",
                              granted: model.trusted, action: model.openAccessibilitySettings)
                PermissionRow(title: "마이크", detail: "녹음",
                              granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
                PermissionRow(title: "화면 및 시스템 오디오 녹음", detail: "컴퓨터 소리 녹음",
                              granted: CGPreflightScreenCaptureAccess(), action: recorder.openScreenPermissionSettings)
                ClipboardPermissionRow(history: .shared)
            }
        }
    }
}

private struct UpdateCard: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Card(title: "업데이트") {
            HStack {
                Text("현재 버전 \(Updater.version)").monospacedDigit()
                Spacer()
                Button("지금 확인", action: updater.checkForUpdates)
                    .controlSize(.small).disabled(!updater.canCheck)
            }
            Toggle("자동으로 업데이트 확인 (하루 한 번)",
                   isOn: Binding(get: { updater.automaticallyChecks }, set: updater.setAutomaticallyChecks))
                .toggleStyle(.switch)
            Link("릴리스 노트 보기", destination: URL(string: "https://github.com/clo3olb/toolbelt/releases")!)
                .font(.callout)
        }
    }
}

/// 클립보드 접근 (macOS 26): "항상 허용"이어야 기록이 매번 묻지 않고 동작한다
struct ClipboardPermissionRow: View {
    @ObservedObject var history: ClipboardHistory

    var body: some View {
        PermissionRow(title: "클립보드 접근", detail: "클립보드 기록 — 시스템 설정에서 '항상 허용'",
                      granted: history.accessGranted, action: history.requestAccess)
            .onAppear(perform: history.refreshAccess)
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? "설정 보기" : "허용하기", action: action).controlSize(.small)
        }
    }
}
