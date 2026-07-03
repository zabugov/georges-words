// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Parakeet (FluidAudio) is opt-in: it pulls in C/C++ dependencies that don't
// build cleanly on every macOS SDK, and must never block the default build.
// Enable it with:  GW_PARAKEET=1 ./app/build.sh
let parakeetEnabled = ProcessInfo.processInfo.environment["GW_PARAKEET"] == "1"

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", .upToNextMajor(from: "0.9.0"))
]
var targetDependencies: [Target.Dependency] = [
    .product(name: "WhisperKit", package: "WhisperKit")
]
var swiftSettings: [SwiftSetting] = []

if parakeetEnabled {
    // Pinned to 0.15.x: pre-1.0 minor bumps change the API (0.12 → 0.15
    // moved decoder state to the caller), so don't float across them.
    dependencies.append(.package(url: "https://github.com/FluidInference/FluidAudio.git", "0.15.4"..<"0.16.0"))
    targetDependencies.append(.product(name: "FluidAudio", package: "FluidAudio"))
    swiftSettings.append(.define("PARAKEET"))
}

let package = Package(
    name: "GeorgesWords",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: dependencies,
    targets: [
        .executableTarget(
            name: "GeorgesWords",
            dependencies: targetDependencies,
            path: "Sources/GeorgesWords",
            swiftSettings: swiftSettings
        )
    ]
)
