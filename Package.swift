// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Verbatim",
    platforms: [.macOS(.v26)],
    dependencies: [
        // WhisperKit lives in the argmax-oss-swift package. Pinned on purpose.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
        // FluidAudio runs NVIDIA Parakeet for live text. Pinned on purpose.
        // traits: [] leaves out its text-to-speech, speaker and text-normalising
        // parts, which Verbatim doesn't use (smaller app).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0", traits: []),
    ],
    targets: [
        .executableTarget(
            name: "Verbatim",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Verbatim",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
