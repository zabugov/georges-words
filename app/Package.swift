// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GeorgesWords",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", .upToNextMajor(from: "0.9.0"))
    ],
    targets: [
        .executableTarget(
            name: "GeorgesWords",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/GeorgesWords"
        )
    ]
)
