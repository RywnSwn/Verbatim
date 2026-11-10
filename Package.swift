// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Verbatim",
    platforms: [.macOS(.v26)],
    dependencies: [
        // FluidAudio runs NVIDIA Parakeet, for live text and for files. Pinned on purpose.
        // (WhisperKit was removed in step 5c: Parakeet only.)
        // traits: ["Diarizer"] keeps its speaker part (step 7: Sortformer, who
        // spoke when) and leaves out text-to-speech and text-normalising,
        // which Verbatim doesn't use (smaller app).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0", traits: ["Diarizer"]),
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
