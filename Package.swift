// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Toolbelt",
    platforms: [.macOS("26.0")],
    dependencies: [
        // 자동 업데이트 (GitHub Releases의 appcast.xml을 확인)
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMinor(from: "2.9.6")),
    ],
    targets: [
        .executableTarget(
            name: "Toolbelt",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Toolbelt",
            // 앱 번들의 Contents/Frameworks에 넣은 Sparkle.framework를 찾도록
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
