// swift-tools-version: 6.2
// Punctuation test (2026-11-20): does Parakeet write capitals, commas and
// quotes, live vs batch vs rolling batch vs TDT v3? Runs on the CI Mac only.
// Not part of the app.
import PackageDescription

let package = Package(
    name: "PunctTest",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Same pin as the app.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0", traits: ["Diarizer"]),
    ],
    targets: [
        .executableTarget(
            name: "PunctTest",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
