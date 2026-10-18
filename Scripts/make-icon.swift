// 앱 아이콘 원본(1024×1024 PNG)을 그린다. `make icon`이 이 결과로 Resources/AppIcon.icns를 만든다.
// 사용: swift Scripts/make-icon.swift <출력.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS 아이콘 그리드: 1024 캔버스 안에 824 크기 둥근 사각형, 아래로 살짝 그림자.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor.black.setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

// 배경: 위 인디고 → 아래 진한 남색.
NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.45, blue: 0.98, alpha: 1),
    NSColor(srgbRed: 0.16, green: 0.20, blue: 0.55, alpha: 1),
])!.draw(in: tilePath, angle: -90)

// 위쪽 은은한 하이라이트.
NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.22),
    NSColor.white.withAlphaComponent(0),
])!.draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// 가운데 심볼 (메뉴바 아이콘과 같은 모티프).
let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "wrench.and.screwdriver.fill", accessibilityDescription: nil)!
    .withSymbolConfiguration(config)!
let s = symbol.size
let scale = min(500 / s.width, 500 / s.height)
let symbolRect = NSRect(
    x: tile.midX - s.width * scale / 2, y: tile.midY - s.height * scale / 2,
    width: s.width * scale, height: s.height * scale)

NSGraphicsContext.saveGraphicsState()
let glyphShadow = NSShadow()
glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
glyphShadow.shadowOffset = NSSize(width: 0, height: -10)
glyphShadow.shadowBlurRadius = 20
glyphShadow.set()
symbol.draw(in: symbolRect)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
