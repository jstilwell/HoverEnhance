// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HoverEnhance",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "HoverEnhance",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework goes in the app's Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "HoverEnhanceTests", dependencies: ["HoverEnhance"]),
    ]
)
