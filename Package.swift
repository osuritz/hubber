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
    targets: [
        .executableTarget(
            name: "Hubber",
            path: "Sources/Hubber"
        ),
        .testTarget(
            name: "HubberTests",
            dependencies: ["Hubber"],
            path: "Tests/HubberTests"
        )
    ]
)
