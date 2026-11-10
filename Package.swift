// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Verbatim",
    platforms: [.macOS(.v26)],
    dependencies: [
        // FluidAudio runs NVIDIA Parakeet, for live text and for whole files.
        // Pinned on purpose.
        // traits: [] leaves out its text-to-speech, speaker and text-normalising
        // parts, which Verbatim doesn't use (smaller app).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0", traits: []),
    ],
    targets: [
        .executableTarget(
            name: "Verbatim",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Verbatim",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
