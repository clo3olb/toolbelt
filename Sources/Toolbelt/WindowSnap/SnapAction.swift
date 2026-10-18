import AppKit
import Carbon.HIToolbox

/// 창 배치 종류 (Rectangle의 목록을 따른다). rawValue는 설정 저장 키이므로 바꾸지 않는다.
enum SnapAction: String, CaseIterable, Codable, Identifiable {
    // 절반
    case leftHalf, rightHalf, topHalf, bottomHalf, centerHalf
    // 모서리
    case topLeft, topRight, bottomLeft, bottomRight
    // 3분할
    case firstThird, centerThird, lastThird, firstTwoThirds, centerTwoThirds, lastTwoThirds
    // 4등분
    case firstFourth, secondFourth, thirdFourth, lastFourth, firstThreeFourths, lastThreeFourths
    // 6분할
    case topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    // 크기
    case maximize, almostMaximize, maximizeHeight, larger, smaller, center, restore
    // 이동 (크기 유지)
    case moveLeft, moveRight, moveUp, moveDown
    // 디스플레이
    case nextDisplay, previousDisplay

    var id: String { rawValue }

    enum Category: String, CaseIterable {
        case halves = "절반", corners = "모서리", thirds = "3분할", fourths = "4등분", sixths = "6분할"
        case size = "크기", move = "이동", display = "디스플레이"
    }

    var category: Category {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf, .centerHalf: return .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return .corners
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds: return .thirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths: return .fourths
        case .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth: return .sixths
        case .maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .center, .restore: return .size
        case .moveLeft, .moveRight, .moveUp, .moveDown: return .move
        case .nextDisplay, .previousDisplay: return .display
        }
    }

    var title: String {
        switch self {
        case .leftHalf: return "왼쪽 절반"
        case .rightHalf: return "오른쪽 절반"
        case .topHalf: return "위쪽 절반"
        case .bottomHalf: return "아래쪽 절반"
        case .centerHalf: return "가운데 절반"
        case .topLeft: return "왼쪽 위"
        case .topRight: return "오른쪽 위"
        case .bottomLeft: return "왼쪽 아래"
        case .bottomRight: return "오른쪽 아래"
        case .firstThird: return "첫 번째 1/3"
        case .centerThird: return "가운데 1/3"
        case .lastThird: return "마지막 1/3"
        case .firstTwoThirds: return "앞쪽 2/3"
        case .centerTwoThirds: return "가운데 2/3"
        case .lastTwoThirds: return "뒤쪽 2/3"
        case .firstFourth: return "첫 번째 1/4"
        case .secondFourth: return "두 번째 1/4"
        case .thirdFourth: return "세 번째 1/4"
        case .lastFourth: return "마지막 1/4"
        case .firstThreeFourths: return "앞쪽 3/4"
        case .lastThreeFourths: return "뒤쪽 3/4"
        case .topLeftSixth: return "왼쪽 위 1/6"
        case .topCenterSixth: return "가운데 위 1/6"
        case .topRightSixth: return "오른쪽 위 1/6"
        case .bottomLeftSixth: return "왼쪽 아래 1/6"
        case .bottomCenterSixth: return "가운데 아래 1/6"
        case .bottomRightSixth: return "오른쪽 아래 1/6"
        case .maximize: return "최대화"
        case .almostMaximize: return "거의 최대화"
        case .maximizeHeight: return "세로 최대화"
        case .larger: return "크게"
        case .smaller: return "작게"
        case .center: return "가운데"
        case .restore: return "원래대로"
        case .moveLeft: return "왼쪽 가장자리로"
        case .moveRight: return "오른쪽 가장자리로"
        case .moveUp: return "위쪽 가장자리로"
        case .moveDown: return "아래쪽 가장자리로"
        case .nextDisplay: return "다음 디스플레이"
        case .previousDisplay: return "이전 디스플레이"
        }
    }

    /// 화면 안에서 차지하는 영역 (왼쪽 위 원점, 0~1). 영역으로 표현되지 않는 동작은 nil.
    var unitRect: CGRect? {
        let third = 1.0 / 3, sixthW = 1.0 / 3
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .centerHalf: return CGRect(x: 0.25, y: 0, width: 0.5, height: 1)
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .firstThird: return CGRect(x: 0, y: 0, width: third, height: 1)
        case .centerThird: return CGRect(x: third, y: 0, width: third, height: 1)
        case .lastThird: return CGRect(x: 2 * third, y: 0, width: third, height: 1)
        case .firstTwoThirds: return CGRect(x: 0, y: 0, width: 2 * third, height: 1)
        case .centerTwoThirds: return CGRect(x: third / 2, y: 0, width: 2 * third, height: 1)
        case .lastTwoThirds: return CGRect(x: third, y: 0, width: 2 * third, height: 1)
        case .firstFourth: return CGRect(x: 0, y: 0, width: 0.25, height: 1)
        case .secondFourth: return CGRect(x: 0.25, y: 0, width: 0.25, height: 1)
        case .thirdFourth: return CGRect(x: 0.5, y: 0, width: 0.25, height: 1)
        case .lastFourth: return CGRect(x: 0.75, y: 0, width: 0.25, height: 1)
        case .firstThreeFourths: return CGRect(x: 0, y: 0, width: 0.75, height: 1)
        case .lastThreeFourths: return CGRect(x: 0.25, y: 0, width: 0.75, height: 1)
        case .topLeftSixth: return CGRect(x: 0, y: 0, width: sixthW, height: 0.5)
        case .topCenterSixth: return CGRect(x: sixthW, y: 0, width: sixthW, height: 0.5)
        case .topRightSixth: return CGRect(x: 2 * sixthW, y: 0, width: sixthW, height: 0.5)
        case .bottomLeftSixth: return CGRect(x: 0, y: 0.5, width: sixthW, height: 0.5)
        case .bottomCenterSixth: return CGRect(x: sixthW, y: 0.5, width: sixthW, height: 0.5)
        case .bottomRightSixth: return CGRect(x: 2 * sixthW, y: 0.5, width: sixthW, height: 0.5)
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .almostMaximize: return CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        default: return nil
        }
    }

    /// 영역이 아닌 동작의 아이콘
    var symbol: String {
        switch self {
        case .maximizeHeight: return "arrow.up.and.down.square"
        case .larger: return "plus.square"
        case .smaller: return "minus.square"
        case .center: return "rectangle.center.inset.filled"
        case .restore: return "arrow.uturn.backward.square"
        case .moveLeft: return "arrow.left.to.line"
        case .moveRight: return "arrow.right.to.line"
        case .moveUp: return "arrow.up.to.line"
        case .moveDown: return "arrow.down.to.line"
        case .nextDisplay: return "rectangle.righthalf.inset.filled.arrow.right"
        case .previousDisplay: return "rectangle.lefthalf.inset.filled.arrow.left"
        default: return "rectangle"
        }
    }

    /// Rectangle 기본 단축키 (⌃⌥ 조합). 없으면 nil = 기본으로 꺼짐.
    var defaultHotKey: HotKey? {
        let co = HotKey.controlOption
        switch self {
        case .leftHalf: return HotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: co)
        case .rightHalf: return HotKey(keyCode: UInt32(kVK_RightArrow), modifiers: co)
        case .topHalf: return HotKey(keyCode: UInt32(kVK_UpArrow), modifiers: co)
        case .bottomHalf: return HotKey(keyCode: UInt32(kVK_DownArrow), modifiers: co)
        case .topLeft: return HotKey(keyCode: UInt32(kVK_ANSI_U), modifiers: co)
        case .topRight: return HotKey(keyCode: UInt32(kVK_ANSI_I), modifiers: co)
        case .bottomLeft: return HotKey(keyCode: UInt32(kVK_ANSI_J), modifiers: co)
        case .bottomRight: return HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: co)
        case .firstThird: return HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: co)
        case .centerThird: return HotKey(keyCode: UInt32(kVK_ANSI_F), modifiers: co)
        case .lastThird: return HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: co)
        case .firstTwoThirds: return HotKey(keyCode: UInt32(kVK_ANSI_E), modifiers: co)
        case .lastTwoThirds: return HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: co)
        case .maximize: return HotKey(keyCode: UInt32(kVK_Return), modifiers: co)
        case .maximizeHeight: return HotKey(keyCode: UInt32(kVK_UpArrow), modifiers: co | UInt32(shiftKey))
        case .smaller: return HotKey(keyCode: UInt32(kVK_ANSI_Minus), modifiers: co)
        case .larger: return HotKey(keyCode: UInt32(kVK_ANSI_Equal), modifiers: co)
        case .center: return HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: co)
        case .restore: return HotKey(keyCode: UInt32(kVK_Delete), modifiers: co)
        case .nextDisplay: return HotKey(keyCode: UInt32(kVK_RightArrow), modifiers: HotKey.controlOptionCommand)
        case .previousDisplay: return HotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: HotKey.controlOptionCommand)
        default: return nil
        }
    }

    /// 화면의 사용 가능 영역(Cocoa 좌표, 왼쪽 아래 원점)에서 목표 프레임. 디스플레이 이동·원래대로는 WindowMover가 처리.
    func targetFrame(in visible: CGRect, current: CGRect) -> CGRect {
        if let u = unitRect {
            let x = visible.minX + u.minX * visible.width
            let width = u.width * visible.width
            let height = u.height * visible.height
            let y = visible.maxY - (u.minY + u.height) * visible.height
            return CGRect(x: x, y: y, width: width, height: height).integral
        }
        let step: CGFloat = 30
        let w = min(current.width, visible.width)
        let h = min(current.height, visible.height)
        switch self {
        case .maximizeHeight:
            return CGRect(x: current.minX, y: visible.minY, width: w, height: visible.height)
        case .larger:
            return current.insetBy(dx: -step, dy: -step).intersection(visible)
        case .smaller:
            let shrunk = current.insetBy(dx: step, dy: step)
            return shrunk.width >= 200 && shrunk.height >= 150 ? shrunk : current
        case .center:
            return CGRect(x: visible.midX - w / 2, y: visible.midY - h / 2, width: w, height: h)
        case .moveLeft:
            return CGRect(x: visible.minX, y: clamp(current.minY, visible.minY, visible.maxY - h), width: w, height: h)
        case .moveRight:
            return CGRect(x: visible.maxX - w, y: clamp(current.minY, visible.minY, visible.maxY - h), width: w, height: h)
        case .moveUp:
            return CGRect(x: clamp(current.minX, visible.minX, visible.maxX - w), y: visible.maxY - h, width: w, height: h)
        case .moveDown:
            return CGRect(x: clamp(current.minX, visible.minX, visible.maxX - w), y: visible.minY, width: w, height: h)
        default:
            return current
        }
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), max(lo, hi)) }
}
