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
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Hubber",
            dependencies: [
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Hubber"
        ),
        .testTarget(
            name: "HubberTests",
            dependencies: ["Hubber"],
            path: "Tests/HubberTests"
        )
    ]
)
