// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Parakeet (FluidAudio) is ON by default — validated on the owner's machine
// 2026-07-03. If its C/C++ deps ever break a build, opt out with:
//   GW_PARAKEET=0 ./app/build.sh
let parakeetEnabled = ProcessInfo.processInfo.environment["GW_PARAKEET"] != "0"

var dependencies: [Package.Dependency] = [
    // Pinned exactly: pre-1.0, minor bumps can break the API. Update
    // deliberately, with a local test of the Whisper fallback engine.
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "0.18.0")
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
        ),
        .testTarget(
            name: "GeorgesWordsTests",
            dependencies: ["GeorgesWords"],
            path: "Tests/GeorgesWordsTests"
        )
    ]
)
