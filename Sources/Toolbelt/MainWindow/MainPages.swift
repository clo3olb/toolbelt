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
                    ThermometerGauge(model: model)
                }
                .padding(.vertical, 6)
            }
            Card(title: "온도·팬") {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.cpuTemperature.map { "\(Int($0.rounded()))°C" } ?? "–")
                            .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Thermal.color(model.cpuTemperature))
                        Text("CPU 코어 온도").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Thermal.stateName(model.thermalState)).font(.title3.weight(.semibold))
                            .foregroundStyle(model.thermalState == .nominal ? Color.primary : Thermal.stateColor(model.thermalState))
                        Text("발열 상태 (macOS)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                ForEach(Array(model.fans.enumerated()), id: \.offset) { index, fan in
                    HStack(spacing: 10) {
                        Text("팬 \(index + 1)").frame(width: 40, alignment: .leading)
                        UsageBar(ratio: fan.max > fan.min ? (fan.current - fan.min) / (fan.max - fan.min) : 0, tint: .teal)
                        Text(Thermal.rpm(fan.current)).monospacedDigit().frame(width: 90, alignment: .trailing)
                    }
                    .font(.callout)
                }
                if !model.fans.isEmpty, let fan = model.fans.first {
                    Text("막대는 최소 \(Thermal.rpm(fan.min)) ~ 최대 \(Thermal.rpm(fan.max)) 범위").font(.caption).foregroundStyle(.secondary)
                }
                Text("CPU 온도는 SMC 코어 센서들의 중앙값입니다. 70°C 이상 주황, 85°C 이상 빨강. Apple Silicon은 온도 공개 API가 없어 비공개 경로로 읽으므로 macOS 업데이트 후 '–'로 보일 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                CallTargetsEditor(recorder: recorder)
                MeetingKeywordsEditor(recorder: recorder)
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

/// 자동 녹음할 앱·브라우저를 고른다. 설치된 것만 보여준다.
private struct CallTargetsEditor: View {
    @ObservedObject var recorder: RecordingController
    @State private var liveApps: [CallApps.CustomApp] = []
    @State private var notice: String?
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// 기본 앱은 설치된 것만, 직접 추가한 앱은 항상 보인다
    private var targets: [CallApps.Target] {
        _ = recorder.customCallApps
        return CallApps.targets.filter { $0.isCustom || $0.isInstalled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("자동 녹음할 프로그램").font(.callout.weight(.medium))
            Text("켜 둔 프로그램이 마이크를 쓰면 통화로 보고 녹음합니다. 브라우저는 창 제목에 아래 회의 서비스의 단어가 있을 때만입니다. 목록에 없는 통화 앱은 '앱 추가…'로 넣으세요.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            group("통화 앱", targets.filter { !$0.isBrowser })
            HStack(spacing: 8) {
                Button("앱 추가…", action: chooseApp).controlSize(.small)
                if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
            // 지금 마이크를 쓰는데 목록에 없는 앱 → 바로 추가
            if !liveApps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("지금 마이크를 쓰는 앱 (목록에 없음)").font(.caption.weight(.medium))
                    ForEach(liveApps, id: \.bundleID) { app in
                        HStack {
                            Text(app.name).font(.callout)
                            Text(app.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Spacer()
                            Button("추가") { recorder.addCustomCallApp(app); refresh() }.controlSize(.small)
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }
            group("브라우저", targets.filter(\.isBrowser))
        }
        .disabled(!recorder.autoRecordCalls)
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [CallApps.Target]) -> some View {
        if !items.isEmpty {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(items) { target in
                    HStack(spacing: 4) {
                        Toggle(target.name, isOn: Binding(get: { !recorder.disabledCallTargets.contains(target.id) },
                                                          set: { recorder.setCallTarget(target.id, enabled: $0) }))
                            .toggleStyle(.checkbox)
                        if target.isCustom {
                            Button { recorder.removeCustomCallApp(bundleID: target.id) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("목록에서 빼기")
                        }
                    }
                }
            }
        }
    }

    private func refresh() {
        liveApps = CallApps.untrackedAppsUsingMicrophone()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "추가"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let app = CallApps.customApp(at: url) {
            recorder.addCustomCallApp(app)
            notice = nil
        } else {
            notice = "이미 목록에 있거나 앱 정보를 읽지 못했습니다."
        }
    }
}

/// 브라우저 회의 서비스: 브라우저가 마이크를 쓸 때 창 제목에 서비스의 단어(별명)가 있으면 그 이름으로 자동 녹음한다.
private struct MeetingKeywordsEditor: View {
    @ObservedObject var recorder: RecordingController
    @State private var newService = ""
    @State private var liveBrowsers: [(browser: String, titles: [String])] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("브라우저 회의 서비스").font(.callout.weight(.medium))
            Text("브라우저로 통화할 때 창 제목에 서비스의 단어 중 하나가 있으면 그 서비스 이름으로 자동 녹음합니다 (대소문자 무시, 위에서부터 먼저 맞는 것). 녹음이 시작된 뒤에는 다른 탭으로 옮겨도 브라우저가 마이크를 쓰는 동안 계속 녹음합니다.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            ForEach($recorder.meetingServices) { $service in
                MeetingServiceRow(service: $service) {
                    recorder.meetingServices.removeAll { $0.id == service.id }
                }
            }

            HStack(spacing: 6) {
                TextField("새 서비스 이름 (예: 사내 회의)", text: $newService).textFieldStyle(.roundedBorder).frame(width: 200)
                    .onSubmit(addService)
                Button("서비스 추가", action: addService).controlSize(.small)
                    .disabled(newService.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("기본 서비스 복원", action: recorder.restoreDefaultMeetingServices).controlSize(.small)
            }

            // 지금 브라우저로 통화 중이면 창 제목을 보여줘 어떤 단어를 넣을지 알 수 있게 한다
            if !liveBrowsers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(liveBrowsers, id: \.browser) { entry in
                        Text("지금 마이크를 쓰는 브라우저: \(entry.browser)").font(.caption.weight(.medium))
                        ForEach(entry.titles, id: \.self) { title in
                            Text("• \(title)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        if entry.titles.isEmpty {
                            Text("창 제목을 읽지 못했습니다 (손쉬운 사용 권한 확인)").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func addService() {
        recorder.addMeetingService(name: newService)
        newService = ""
    }

    private func refresh() {
        liveBrowsers = CallApps.browsersUsingMicrophone()
    }
}

/// 회의 서비스 한 줄: 켜기 · 이름 · 단어(별명) 칩 · 단어 추가 · 삭제
private struct MeetingServiceRow: View {
    @Binding var service: MeetingService
    let onDelete: () -> Void
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("", isOn: $service.enabled).toggleStyle(.checkbox).labelsHidden()
            TextField("이름", text: $service.name).textFieldStyle(.roundedBorder).frame(width: 130)
            FlowChips(words: service.keywords) { word in service.keywords.removeAll { $0 == word } }
            TextField("단어 추가", text: $draft).textFieldStyle(.roundedBorder).frame(width: 100)
                .onSubmit(addWord)
            Spacer(minLength: 0)
            Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless).help("서비스 삭제")
        }
        .opacity(service.enabled ? 1 : 0.5)
    }

    private func addWord() {
        let word = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !word.isEmpty, !service.keywords.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        service.keywords.append(word)
    }
}

/// 지울 수 있는 단어 칩들 (넘치면 다음 줄로)
private struct FlowChips: View {
    let words: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(words, id: \.self) { word in
                HStack(spacing: 3) {
                    Text(word).font(.caption)
                    Button { onRemove(word) } label: { Image(systemName: "xmark.circle.fill").font(.caption) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, point) in zip(subviews, arrange(bounds.width, subviews).points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
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
