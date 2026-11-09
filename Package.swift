// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Verbatim",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Verbatim",
            path: "Sources/Verbatim"
        )
    ]
)
