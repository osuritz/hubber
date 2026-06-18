// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Hubber",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hubber", targets: ["Hubber"])
    ],
    dependencies: [
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Hubber",
            dependencies: [
                .product(name: "TelemetryDeck", package: "SwiftSDK")
            ],
            path: "Sources/Hubber",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "HubberTests",
            dependencies: ["Hubber"],
            path: "Tests/HubberTests"
        )
    ]
)
