// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Verbatim",
    platforms: [.macOS(.v26)],
    dependencies: [
        // WhisperKit lives in the argmax-oss-swift package. Pinned on purpose.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "Verbatim",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/Verbatim",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
