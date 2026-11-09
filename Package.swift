// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Verbatim",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Verbatim",
            path: "Sources/Verbatim",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
