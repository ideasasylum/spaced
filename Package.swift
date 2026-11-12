// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spaced",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.3.0"),
    ],
    targets: [
        .target(
            name: "SpacedCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .target(name: "SpacedUI", dependencies: ["SpacedCore", "Highlightr"]),
        .executableTarget(name: "SpacedApp", dependencies: ["SpacedUI"]),
        .executableTarget(name: "SpacedCLI", dependencies: ["SpacedCore"]),
        .testTarget(name: "SpacedCoreTests", dependencies: ["SpacedCore"]),
    ],
    swiftLanguageModes: [.v5]
)
