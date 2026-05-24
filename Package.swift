// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Needle",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Needle", targets: ["Needle"]),
        .executable(name: "NeedleCoreCheck", targets: ["NeedleCoreCheck"]),
        .library(name: "SearchCore", targets: ["SearchCore"])
    ],
    targets: [
        .target(
            name: "SearchCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "Needle",
            dependencies: ["SearchCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "NeedleCoreCheck",
            dependencies: ["SearchCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SearchCoreTests",
            dependencies: ["SearchCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
