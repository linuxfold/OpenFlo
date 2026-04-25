// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenFlo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OpenFloCore", targets: ["OpenFloCore"]),
        .executable(name: "OpenFlo", targets: ["OpenFloApp"]),
        .executable(name: "OpenFloInspect", targets: ["OpenFloInspect"]),
        .executable(name: "OpenFloCoreSmokeTests", targets: ["OpenFloCoreSmokeTests"])
    ],
    targets: [
        .target(
            name: "OpenFloCore",
            path: "Sources/OpenFloCore"
        ),
        .executableTarget(
            name: "OpenFloApp",
            dependencies: ["OpenFloCore"],
            path: "Sources/OpenFloApp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "OpenFloInspect",
            dependencies: ["OpenFloCore"],
            path: "Sources/OpenFloInspect"
        ),
        .executableTarget(
            name: "OpenFloCoreSmokeTests",
            dependencies: ["OpenFloCore"],
            path: "Sources/OpenFloCoreSmokeTests"
        )
    ]
)
