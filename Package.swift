// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Toolbelt",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Toolbelt", path: "Sources/Toolbelt")
    ]
)
