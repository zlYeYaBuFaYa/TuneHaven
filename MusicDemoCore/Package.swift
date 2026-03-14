// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MusicDemoCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MusicDemoCore", targets: ["MusicDemoCore"]),
    ],
    targets: [
        .target(
            name: "MusicDemoCore",
            dependencies: [],
            path: "Sources/MusicDemoCore"
        ),
        .testTarget(
            name: "MusicDemoCoreTests",
            dependencies: ["MusicDemoCore"],
            path: "Tests/MusicDemoCoreTests"
        ),
    ]
)
