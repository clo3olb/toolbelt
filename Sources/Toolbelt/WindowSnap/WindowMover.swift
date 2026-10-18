import AppKit
import ApplicationServices

enum WindowMover {
    static func perform(_ action: SnapAction) {
        guard AXIsProcessTrusted() else {
            Permissions.prompt()
            return
        }
        guard let window = focusedWindow(),
              let axFrame = frame(of: window) else {
            NSSound.beep()
            return
        }

        let cocoaFrame = toCocoa(axFrame)
        guard let screen = screen(containing: cocoaFrame) ?? NSScreen.main else { return }
        let key = restoreKey(window)

        var cocoaTarget: CGRect
        switch action {
        case .restore:
            // 처음 배치하기 전 크기·위치로
            guard let original = restoreFrames.removeValue(forKey: key) else { NSSound.beep(); return }
            apply(original, to: window)
            return
        case .nextDisplay, .previousDisplay:
            guard let target = otherScreen(from: screen, next: action == .nextDisplay) else { NSSound.beep(); return }
            cocoaTarget = moved(cocoaFrame, from: screen.visibleFrame, to: target.visibleFrame)
        default:
            cocoaTarget = action.targetFrame(in: screen.visibleFrame, current: cocoaFrame)
            // 이미 같은 쪽 절반에 붙어 있으면 그 방향의 옆 모니터로 넘겨 반대쪽 절반에 붙인다.
            if let next = overflow(action, frame: cocoaFrame, target: cocoaTarget, on: screen) {
                cocoaTarget = next
            }
        }

        // "원래대로"를 위해 처음 배치하기 전 프레임을 기억한다 (연속 배치 중에는 덮어쓰지 않음)
        if restoreFrames[key] == nil { restoreFrames[key] = axFrame }
        apply(toAX(cocoaTarget), to: window)
    }

    /// 창별 원래 프레임 (AX 좌표). 앱 pid + 창 요소 해시로 구분한다.
    private static var restoreFrames: [String: CGRect] = [:]

    private static func restoreKey(_ window: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return "\(pid)-\(CFHash(window))"
    }

    private static func apply(_ target: CGRect, to window: AXUIElement) {
        // 일부 앱은 크기 제약 때문에 위치/크기 순서에 따라 결과가 달라지므로 크기를 두 번 적용한다.
        setSize(target.size, of: window)
        setPosition(target.origin, of: window)
        setSize(target.size, of: window)
    }

    // MARK: - 다음/이전 디스플레이

    /// 화면을 왼쪽→오른쪽(같으면 위→아래) 순서로 놓고 다음/이전 화면 (끝에서는 처음으로 돈다)
    private static func otherScreen(from screen: NSScreen, next: Bool) -> NSScreen? {
        let screens = NSScreen.screens.sorted { a, b in
            a.frame.minX != b.frame.minX ? a.frame.minX < b.frame.minX : a.frame.maxY > b.frame.maxY
        }
        guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return nil }
        return screens[(index + (next ? 1 : -1) + screens.count) % screens.count]
    }

    /// 화면 안 상대 위치를 유지하며 옮긴다. 새 화면보다 크면 줄인다.
    private static func moved(_ frame: CGRect, from old: CGRect, to new: CGRect) -> CGRect {
        let w = min(frame.width, new.width)
        let h = min(frame.height, new.height)
        let rx = old.width > frame.width ? (frame.minX - old.minX) / (old.width - frame.width) : 0
        let ry = old.height > frame.height ? (frame.minY - old.minY) / (old.height - frame.height) : 0
        return CGRect(x: new.minX + max(0, min(rx, 1)) * (new.width - w),
                      y: new.minY + max(0, min(ry, 1)) * (new.height - h),
                      width: w, height: h).integral
    }

    // MARK: - 옆 모니터로 넘기기

    /// 좌/우 절반 동작에서 창이 이미 목표 위치에 있으면, 그 방향 옆 화면의 반대쪽 절반 프레임을 돌려준다.
    private static func overflow(_ action: SnapAction, frame: CGRect, target: CGRect, on screen: NSScreen) -> CGRect? {
        let opposite: SnapAction
        let goRight: Bool
        switch action {
        case .leftHalf: opposite = .rightHalf; goRight = false
        case .rightHalf: opposite = .leftHalf; goRight = true
        default: return nil
        }
        // 터미널 등 글자 단위로 크기가 정해지는 앱은 정확히 절반이 안 되므로 여유를 둔다.
        let tolerance: CGFloat = 20
        guard abs(frame.minX - target.minX) <= tolerance,
              abs(frame.maxX - target.maxX) <= tolerance else { return nil }
        guard let next = neighbor(of: screen, toRight: goRight) else { return nil }
        return opposite.targetFrame(in: next.visibleFrame, current: frame)
    }

    /// 지정한 방향에 있는 가장 가까운 화면. 세로로 겹치는 화면을 우선한다.
    private static func neighbor(of screen: NSScreen, toRight: Bool) -> NSScreen? {
        let f = screen.frame
        let candidates = NSScreen.screens.filter { s in
            s != screen && (toRight ? s.frame.midX > f.maxX - 1 : s.frame.midX < f.minX + 1)
        }
        func distance(_ s: NSScreen) -> CGFloat {
            toRight ? s.frame.minX - f.maxX : f.minX - s.frame.maxX
        }
        let overlapping = candidates.filter { $0.frame.maxY > f.minY && $0.frame.minY < f.maxY }
        return (overlapping.isEmpty ? candidates : overlapping).min { distance($0) < distance($1) }
    }

    // MARK: - Accessibility

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value else { return nil }
        return (value as! AXUIElement)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private static func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    private static func setSize(_ size: CGSize, of window: AXUIElement) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }

    // MARK: - 좌표 변환
    // AX: 주 화면 좌상단 원점, y 아래로 증가 / Cocoa: 주 화면 좌하단 원점, y 위로 증가

    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private static func toCocoa(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private static func toAX(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let s = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return s }
        // 중심이 화면 밖이면 가장 많이 겹치는 화면
        return NSScreen.screens.max { a, b in
            let ia = a.frame.intersection(rect), ib = b.frame.intersection(rect)
            return ia.width * ia.height < ib.width * ib.height
        }
    }
}

enum Permissions {
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
