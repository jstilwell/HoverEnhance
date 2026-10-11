// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HoverEnhance",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "HoverEnhance"),
    ]
)
