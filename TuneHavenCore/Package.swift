// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TuneHavenCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TuneHavenCore", targets: ["TuneHavenCore"]),
    ],
    targets: [
        .target(
            name: "TuneHavenCore",
            dependencies: [],
            path: "Sources/TuneHavenCore"
        ),
        .testTarget(
            name: "TuneHavenCoreTests",
            dependencies: ["TuneHavenCore"],
            path: "Tests/TuneHavenCoreTests"
        ),
    ]
)
