// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "soundway",
    products: [
        .executable(name: "soundway", targets: ["soundway"]),
        .library(name: "SoundwayCore", targets: ["SoundwayCore"])
    ],
    targets: [
        .target(
            name: "SoundwayCore"
        ),
        .executableTarget(
            name: "soundway",
            dependencies: ["SoundwayCore"]
        ),
        .testTarget(
            name: "SoundwayCoreTests",
            dependencies: ["SoundwayCore"]
        )
    ]
)
