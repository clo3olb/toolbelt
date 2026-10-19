import SwiftUI

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var layout = PanelLayout.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !model.trusted { PermissionBanner(model: model) }
            ForEach(layout.visible) { feature in
                FeatureSection(feature: feature, model: model)
            }
            if layout.visible.isEmpty {
                Text("설정에서 팝오버에 표시할 기능을 고르세요").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - 머리글 / 하단

    private var header: some View {
        HStack(spacing: 8) {
            AppBadge()
            Text("Toolbelt").font(.headline)
            Spacer()
            Button { model.openMainWindow(nil) } label: { Image(systemName: "macwindow") }
                .buttonStyle(.borderless).help("Toolbelt 창 열기")
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Button { model.openMainWindow(.settings) } label: { Label("설정", systemImage: "gearshape") }
                    .controlSize(.small)
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .controlSize(.small)
            }
        }
    }
}

/// 팝오버의 기능별 섹션
struct FeatureSection: View {
    let feature: FeatureID
    @ObservedObject var model: PanelModel

    var body: some View {
        switch feature {
        case .recording: RecordingSection(controller: .shared)
        case .clipboard: ClipboardPanelSection(history: .shared, model: model)
        case .system: SystemPanelSection(model: model)
        case .storage: StoragePanelSection(model: model)
        case .windowSnap: WindowSnapPanelSection(model: model)
        case .display: DisplayPanelSection(model: model)
        case .keyboard: KeyboardPanelSection(model: model)
        }
    }
}

struct AppBadge: View {
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: "wrench.and.screwdriver.fill")
            .font(.system(size: size * 0.54, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.45, blue: 0.98),
                                                  Color(red: 0.16, green: 0.20, blue: 0.55)],
                                         startPoint: .top, endPoint: .bottom))
            )
    }
}

struct PermissionBanner: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("창 배치에 손쉬운 사용 권한이 필요합니다").font(.caption)
            Spacer()
            Button("허용하기", action: model.openAccessibilitySettings).controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

// MARK: - 클립보드

struct ClipboardPanelSection: View {
    @ObservedObject var history: ClipboardHistory
    @ObservedObject var model: PanelModel

    var body: some View {
        PanelSection("클립보드") {
            Button("모든 기록") { model.openMainWindow(.feature(.clipboard)) }
                .buttonStyle(.link).font(.caption)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if !history.isEnabled {
                    HStack {
                        Text("복사한 텍스트를 기록합니다").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("켜기") { history.setEnabled(true) }.controlSize(.small)
                    }
                } else {
                    Toggle(isOn: Binding(get: { !history.isPaused }, set: { history.setPaused(!$0) })) {
                        Text(history.isPaused ? "기록 일시정지됨" : "기록 중").font(.callout)
                    }
                    .toggleStyle(.switch).controlSize(.mini)
                    if let notice = history.notice {
                        Text(notice).font(.caption.weight(.medium)).foregroundStyle(.red)
                    }
                    if history.items.isEmpty {
                        Text("아직 기록이 없습니다").font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(history.items.prefix(5)) { item in
                                ClipRow(item: item, history: history, compact: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 기록 한 줄. 누르면 다시 클립보드로 (비밀 항목은 확인 후)
struct ClipRow: View {
    let item: ClipItem
    @ObservedObject var history: ClipboardHistory
    var compact = false
    @State private var hovering = false

    private static let time: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isSecret ? "lock.fill" : "doc.on.doc")
                .font(.system(size: 11)).foregroundStyle(item.isSecret ? Color.orange : Color.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview).font(item.isSecret ? .callout.monospaced() : .callout).lineLimit(1).truncationMode(.tail)
                Text([item.label, item.source, Self.time.localizedString(for: item.date, relativeTo: Date())]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !compact {
                if item.isSecret {
                    Button { history.markNormal(item) } label: { Image(systemName: "lock.open") }
                        .buttonStyle(.borderless).help("일반으로 바꾸기 (Touch ID/암호 확인, 다음부터 비밀로 기억하지 않음)")
                } else {
                    Button { history.markSecret(item) } label: { Image(systemName: "lock") }
                        .buttonStyle(.borderless).help("비밀로 바꾸기 (키체인으로 옮기고 가림, 같은 값은 다음에도 비밀로)")
                }
                Button { history.delete(item) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("삭제")
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(hovering ? 0.12 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { history.copy(item) }
        .help(item.isSecret ? "Touch ID 또는 암호 확인 후 복사 (30초 뒤 지움)" : "클릭해서 복사")
    }
}

// MARK: - 시스템

struct SystemPanelSection: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        PanelSection("시스템") {
            Button("활성 상태 보기", action: model.openActivityMonitor)
                .buttonStyle(.link).font(.caption)
        } content: {
            HStack(alignment: .top, spacing: 4) {
                RingGauge(title: "CPU", usage: model.cpu, tint: .blue)
                RingGauge(title: "메모리", usage: model.memory, tint: .green)
                RingGauge(title: "저장 공간", usage: model.storage, tint: .purple)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 저장 장치

struct StoragePanelSection: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        PanelSection("저장 장치") {
            VStack(spacing: 10) {
                ForEach(model.volumes) { volume in
                    VolumeRow(volume: volume, model: model)
                }
                if model.volumes.isEmpty {
                    Text("연결된 디스크가 없습니다").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 디스크 한 줄: 아이콘·이름·용량 막대·남은 용량, 외장이면 꺼내기
struct VolumeRow: View {
    let volume: StorageVolume
    @ObservedObject var model: PanelModel
    var showMenu = true

    private var tint: Color { volume.ratio >= 0.9 ? .red : volume.ratio >= 0.75 ? .orange : .accentColor }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: volume.symbol).font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(volume.name).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer()
                    Text("\(StorageDevices.format(volume.available)) 남음")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                UsageBar(ratio: volume.ratio, tint: tint)
                Text("\(StorageDevices.format(volume.used)) / \(StorageDevices.format(volume.total)) 사용 (\(Int((volume.ratio * 100).rounded()))%)")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            if showMenu {
                Menu {
                    Button("Finder에서 열기") { model.reveal(volume) }
                    if volume.isEjectable { Button("꺼내기") { model.eject(volume) } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
    }
}

/// 사용률 막대 (창이 비활성이어도 색이 유지되도록 직접 그린다)
struct UsageBar: View {
    let ratio: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tint).frame(width: max(geo.size.width * min(max(ratio, 0), 1), 6))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - 창 배치

struct WindowSnapPanelSection: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        PanelSection("창 배치") {
            SnapTiles(model: model)
        }
    }
}

struct SnapTiles: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var settings = WindowSnapSettings.shared

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(settings.enabledActions) { action in
                SnapTile(action: action, hotKey: settings.hotKeys[action]) { model.snap(action) }
                    .disabled(!model.trusted)
            }
        }
        if settings.enabledActions.isEmpty {
            Text("창 배치 페이지에서 쓸 배치를 켜세요").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 디스플레이

struct DisplayPanelSection: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        PanelSection("디스플레이") {
            if model.hasDisabledDisplays {
                Button("모두 다시 연결  ⌃⌥⌘R") { model.displayAction(DisplayCommands.reconnectAll.run) }
                    .buttonStyle(.link).font(.caption)
            }
        } content: {
            VStack(spacing: 6) {
                ForEach(model.displays, id: \.id) { display in
                    DisplayRow(display: display,
                               canDisconnect: model.activeDisplayCount > 1,
                               model: model)
                }
            }
        }
    }
}

// MARK: - 키보드

struct KeyboardPanelSection: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        PanelSection("키보드") {
            CapsLockControl(model: model)
        }
    }
}

struct CapsLockControl: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "capslock").font(.system(size: 16)).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Caps Lock 한/영 전환").font(.callout.weight(.medium))
                    Text("Caps Lock → F19, 누르는 즉시 전환").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { model.capsLockSwitch }, set: model.setCapsLockSwitch))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            if model.capsLockSwitch && !model.capsShortcutReady {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("키보드 단축키… → 입력 소스 → '이전 입력 소스 선택'을 더블클릭하고 Caps Lock을 누르세요.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("설정 열기", action: model.openShortcutSettings).controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.12)))
            }
        }
    }
}

// MARK: - 녹음

struct RecordingSection: View {
    @ObservedObject var controller: RecordingController

    var body: some View {
        PanelSection("녹음") {
            Button("모든 녹음") { MainWindowController.shared.show(.recording) }
                .buttonStyle(.link).font(.caption)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                recordRow
                autoRecordRow
                if let message = controller.errorMessage { errorBanner(message) }
                if !controller.recordings.isEmpty {
                    Divider()
                    VStack(spacing: 6) {
                        ForEach(controller.recordings.prefix(5)) { recording in
                            RecordingRow(recording: recording,
                                         transcription: controller.transcriptionState(of: recording.id),
                                         controller: controller)
                        }
                    }
                }
            }
        }
    }

    private var recordRow: some View {
        HStack(spacing: 12) {
            Button(action: controller.toggle) {
                ZStack {
                    Circle().fill(controller.isRecording ? Color.red.opacity(0.15) : Color.red)
                    if controller.isRecording {
                        RoundedRectangle(cornerRadius: 3).fill(Color.red).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "mic.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(controller.isStarting)
            .help(controller.isRecording ? "녹음 정지" : "녹음 시작")

            VStack(alignment: .leading, spacing: 2) {
                if controller.isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text("녹음 중  \(duration(controller.elapsed))")
                            .font(.callout.weight(.semibold)).monospacedDigit()
                    }
                } else {
                    Text(controller.isStarting ? "녹음 준비 중…" : "녹음 시작").font(.callout.weight(.medium))
                }
                if let autoStatus {
                    Text(autoStatus).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
        }
    }

    private var autoStatus: String? {
        guard let name = controller.autoCallName else { return nil }
        return controller.autoCallEnding ? "\(name) 통화 종료 감지 — 곧 자동 정지" : "\(name) 통화 감지 — 자동 녹음 중"
    }

    private var autoRecordRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.badge.waveform").font(.system(size: 15)).frame(width: 40)
            Text("통화 자동 녹음").font(.callout)
            Spacer()
            Toggle("", isOn: Binding(get: { controller.autoRecordCalls }, set: controller.setAutoRecordCalls))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if controller.needsScreenPermission {
                Button("설정 열기", action: controller.openScreenPermissionSettings).controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

struct RecordingRow: View {
    let recording: Recording
    let transcription: RecordingController.TranscriptionState
    @ObservedObject var controller: RecordingController

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(recording.title ?? Self.dateFormat.string(from: recording.date)).font(.callout).lineLimit(1)
                Text(recording.meta.map { duration($0.duration) } ?? "녹음 정보 없음")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            switch transcription {
            case .running:
                ProgressView().controlSize(.small)
                Text("전사 중…").font(.caption).foregroundStyle(.secondary)
            case .queued:
                Text("전사 대기").font(.caption).foregroundStyle(.secondary)
            case .failed, .none:
                if recording.hasTranscript {
                    Button("전사 보기") { MainWindowController.shared.show(.recording, selectRecording: recording.id) }
                } else {
                    Button(transcription == .failed ? "다시 전사" : "전사") { controller.transcribe(recording) }
                        .disabled(recording.meta == nil)
                }
            }
            Button { MainWindowController.shared.show(.recording, selectRecording: recording.id) } label: { Image(systemName: "macwindow") }
                .help("녹음 창에서 보기")
        }
        .controlSize(.small)
        .disabled(controller.currentRecordingID == recording.id)
    }
}

func duration(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded(.down))
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%02d:%02d", s / 60, s % 60)
}

// MARK: - 구성 요소

/// 제목 + (오른쪽 보조 버튼) + 둥근 배경 카드
struct PanelSection<Accessory: View, Content: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content

    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    init(_ title: String, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.init(title, accessory: { EmptyView() }, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                accessory
            }
            .padding(.horizontal, 4)
            VStack { content }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }
}

/// 원형 사용률 게이지. 75% 이상 주황, 90% 이상 빨강.
struct RingGauge: View {
    let title: String
    let usage: PanelModel.Usage
    let tint: Color

    private var color: Color {
        guard let r = usage.ratio else { return tint }
        return r >= 0.9 ? .red : r >= 0.75 ? .orange : tint
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: usage.ratio ?? 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: usage.ratio)
                Text(usage.ratio.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 62, height: 62)
            Text(title).font(.caption.weight(.medium))
            Text(usage.detail)
                .font(.caption2).foregroundStyle(.secondary)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DisplayRow: View {
    let display: DisplayInfo
    let canDisconnect: Bool
    @ObservedObject var model: PanelModel

    private var status: String {
        display.isMain ? "주 디스플레이" : display.isActive ? "연결됨" : "연결 해제됨"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: display.isActive ? "display" : "display.trianglebadge.exclamationmark")
                .font(.system(size: 18))
                .foregroundStyle(display.isActive ? Color.primary : Color.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(status).font(.caption).foregroundStyle(display.isMain ? Color.accentColor : Color.secondary)
            }
            Spacer(minLength: 4)
            if display.isActive {
                if !display.isMain {
                    Button("주로 설정") { model.displayAction { DisplayManager.makeMain(display) } }
                        .help("주 디스플레이로 설정")
                }
                // 안전장치 1: 마지막 남은 디스플레이는 연결 해제 불가 (DisplayManager에도 가드 있음)
                Button("연결 해제") { model.displayAction { DisplayManager.disconnect(display) } }
                    .disabled(!canDisconnect)
            } else {
                Button("다시 연결") { model.displayAction { DisplayManager.reconnect(display.id) } }
            }
        }
        .controlSize(.small)
    }
}
