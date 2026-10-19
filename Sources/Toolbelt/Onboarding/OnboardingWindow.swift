import AppKit
import AVFoundation
import SwiftUI

/// 첫 실행 안내: 권한 3종 + 선택 기능(기본 꺼짐). 처음 설치한 사용자에게만 자동으로 뜨고, 설정에서 다시 열 수 있다.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private static let doneKey = "onboardingDone"
    /// 이 키들 중 하나라도 있으면 이미 쓰던 사용자로 보고 자동으로 띄우지 않는다
    private static let existingUserKeys = ["capsLockSwitch", "autoRecordCalls", "panelOrder", "snapHotKeys", "disabledDisplays"]

    private var window: NSWindow?
    private let model = PanelModel()

    var shouldShowOnLaunch: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.doneKey) { return false }
        if Self.existingUserKeys.contains(where: { defaults.object(forKey: $0) != nil }) {
            defaults.set(true, forKey: Self.doneKey)
            return false
        }
        return true
    }

    func show() {
        model.refreshAll()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Toolbelt 시작하기"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(model: model, recorder: .shared) { [weak self] in
                self?.finish()
            })
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window?.close()
    }

    /// 닫기 버튼으로 닫아도 다시 자동으로 뜨지 않게 한다 (설정에서 다시 볼 수 있음)
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var recorder: RecordingController
    let done: () -> Void

    /// 권한은 시스템 설정에서 바뀌므로 1초마다 다시 읽는다
    @State private var tick = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var micGranted: Bool { _ = tick; return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    private var screenGranted: Bool { _ = tick; return CGPreflightScreenCaptureAccess() }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        AppBadge(size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Toolbelt에 오신 것을 환영합니다").font(.title2.weight(.bold))
                            Text("메뉴바의 🔧 아이콘에서 모든 기능을 쓸 수 있습니다.").foregroundStyle(.secondary)
                        }
                    }

                    Card(title: "권한") {
                        Text("쓰려는 기능에 필요한 권한만 허용하면 됩니다. 나중에 설정에서 언제든 바꿀 수 있습니다.")
                            .font(.callout).foregroundStyle(.secondary)
                        PermissionRow(title: "손쉬운 사용", detail: "창 배치, 브라우저 회의 감지",
                                      granted: model.trusted) { Permissions.prompt(); model.openAccessibilitySettings() }
                        PermissionRow(title: "마이크", detail: "녹음 (내 목소리)", granted: micGranted) {
                            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                                AVCaptureDevice.requestAccess(for: .audio) { _ in }
                            } else {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                            }
                        }
                        PermissionRow(title: "화면 및 시스템 오디오 녹음", detail: "녹음 (컴퓨터 소리) — 허용 후 Toolbelt를 다시 실행",
                                      granted: screenGranted) {
                            if !CGRequestScreenCaptureAccess() { recorder.openScreenPermissionSettings() }
                        }
                        ClipboardPermissionRow(history: .shared)
                    }

                    Card(title: "선택 기능 (기본 꺼짐)") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: Binding(get: { model.capsLockSwitch }, set: model.setCapsLockSwitch)) {
                                    Text("Caps Lock으로 한/영 전환").font(.callout.weight(.medium))
                                }
                                .toggleStyle(.switch)
                                Text("Caps Lock을 누르는 즉시 입력 소스를 바꿉니다 (대문자 고정은 쓰지 않음). 켠 뒤 시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스 → '이전 입력 소스 선택'을 더블클릭하고 Caps Lock을 누르세요.")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if model.capsLockSwitch {
                                    HStack(spacing: 6) {
                                        Image(systemName: model.capsShortcutReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                            .foregroundStyle(model.capsShortcutReady ? .green : .orange)
                                        Text(model.capsShortcutReady ? "단축키가 지정돼 있습니다" : "아직 단축키가 지정되지 않았습니다").font(.caption)
                                        Spacer()
                                        Button("키보드 설정 열기", action: model.openShortcutSettings).controlSize(.small)
                                    }
                                }
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: Binding(get: { recorder.autoRecordCalls }, set: recorder.setAutoRecordCalls)) {
                                    Text("통화 자동 녹음").font(.callout.weight(.medium))
                                }
                                .toggleStyle(.switch)
                                Text("전화·FaceTime·Slack·카카오톡·Zoom 등 통화 앱이 마이크를 쓰면 자동으로 녹음합니다. 녹음은 이 Mac에만 저장됩니다. 상대방의 동의 등 녹음에 관한 법과 규칙은 사용하는 곳에 따라 다르니 확인하고 쓰세요.")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: Binding(get: { ClipboardHistory.shared.isEnabled },
                                                     set: { ClipboardHistory.shared.setEnabled($0); tick += 1 })) {
                                    Text("클립보드 기록").font(.callout.weight(.medium))
                                }
                                .toggleStyle(.switch)
                                Text("복사한 텍스트를 7일 동안 이 Mac에만 암호화해 보관합니다. API 키·비밀번호처럼 보이는 값은 가려서 키체인에 두고, 다시 쓸 때 Touch ID나 암호를 확인합니다.")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Divider()
                            Toggle(isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled)) {
                                Text("로그인 시 자동 실행").font(.callout.weight(.medium))
                            }
                            .toggleStyle(.switch)
                        }
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("이 안내는 설정 → 일반에서 다시 볼 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("시작하기", action: done).keyboardShortcut(.defaultAction).controlSize(.large)
            }
            .padding(16)
        }
        .frame(width: 560, height: 680)
        .onReceive(timer) { _ in
            tick += 1
            model.trusted = AXIsProcessTrusted()
            model.capsShortcutReady = CapsLockSwitch.isShortcutF19
            ClipboardHistory.shared.refreshAccess()
        }
    }
}
