import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 배치 영역을 그대로 그린 작은 아이콘 (영역이 없는 동작은 SF Symbol)
struct SnapGlyph: View {
    let action: SnapAction
    var size: CGFloat = 22

    var body: some View {
        if let u = action.unitRect {
            let w = size, h = size * 0.72
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.55), lineWidth: 1.2)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: max(u.width * (w - 4), 2), height: max(u.height * (h - 4), 2))
                    .offset(x: 2 + u.minX * (w - 4), y: 2 + u.minY * (h - 4))
            }
            .frame(width: w, height: h)
        } else {
            Image(systemName: action.symbol).font(.system(size: size * 0.7)).frame(width: size, height: size * 0.72)
        }
    }
}

/// 팝오버용 작은 타일: 아이콘만, 마우스를 올리면 이름·단축키
struct SnapTile: View {
    let action: SnapAction
    let hotKey: HotKey?
    let perform: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: perform) {
            SnapGlyph(action: action)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(hovering && isEnabled ? 0.18 : 0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .help(hotKey.map { "\(action.title)  \($0.display)" } ?? action.title)
    }
}

/// 클릭하면 다음에 누르는 키 조합을 단축키로 기록한다. ⌫는 지우기, ⎋는 취소.
struct ShortcutField: View {
    let hotKey: HotKey?
    let onChange: (HotKey?) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleRecording) {
                Text(recording ? "키 입력…" : hotKey?.display ?? "단축키 없음")
                    .font(.callout.monospaced())
                    .foregroundStyle(recording ? Color.accentColor : hotKey == nil ? Color.secondary : Color.primary)
                    .frame(minWidth: 96)
                    .padding(.vertical, 3).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.15)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("클릭한 뒤 단축키를 누르세요 (⌫ 지우기, ⎋ 취소)")
            // 단축키가 없어도 자리를 비워 둬 줄이 맞게 한다
            Button { onChange(nil) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain).help("단축키 지우기")
                .opacity(hotKey != nil && !recording ? 1 : 0)
                .disabled(hotKey == nil || recording)
        }
        .onDisappear(perform: stop)
    }

    private func toggleRecording() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        WindowSnapSettings.shared.suspendHotKeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil   // 기록 중인 키는 다른 곳으로 보내지 않는다
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        WindowSnapSettings.shared.applyHotKeys()
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let code = Int(event.keyCode)
        if flags.isEmpty, code == kVK_Escape { stop(); return }
        if flags.isEmpty, code == kVK_Delete || code == kVK_ForwardDelete { onChange(nil); stop(); return }
        let isFunctionKey = HotKey.keyName(UInt32(code)).range(of: "^F[0-9]+$", options: .regularExpression) != nil
        // 글자만 누른 키는 받지 않는다 (⌃ ⌥ ⌘ 중 하나가 필요). F19는 한/영 전환용이라 제외.
        guard !flags.subtracting(.shift).isEmpty || (isFunctionKey && code != kVK_F19) else { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        onChange(HotKey(keyCode: UInt32(code), modifiers: modifiers))
        stop()
    }
}
