// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Hubber",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Hubber", targets: ["Hubber"]),
        .library(name: "HubberKit", targets: ["HubberKit"]),
        // Phase-0 spike only — NOT built by default swift build / CI.
        // Built only via `make widget-spike` (Scripts/make-widget-spike.sh).
        .executable(name: "HubberWidgetSpike", targets: ["HubberWidgetSpike"]),
    ],
    dependencies: [
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "Hubber",
            dependencies: [
                "HubberKit",
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Hubber",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                // WidgetKit is used by HubberStore to reload widget timelines after each
                // snapshot write. Safe in a menu-bar executable — WidgetCenter calls are
                // no-ops when no widget extension is registered.
                .linkedFramework("WidgetKit", .when(platforms: [.macOS])),
            ]
        ),
        // Phase-0 spike: exercises AppIntentConfiguration + EntityQuery + App Group.
        // Uses WidgetKit + AppIntents — only buildable as a .appex extension,
        // not a plain executable. `swift build --target HubberWidgetSpike` will
        // build the binary but the bundle shape + signing are done by make-widget-spike.sh.
        // FINDING: If this fails to build (missing WidgetKit/AppIntents under pure SPM),
        // that IS the blocker — record it in SPIKE-RESULTS.md.
        .executableTarget(
            name: "HubberWidgetSpike",
            path: "Sources/HubberWidgetSpike",
            swiftSettings: [
                .unsafeFlags(["-framework", "WidgetKit", "-framework", "AppIntents", "-framework", "SwiftUI"],
                             .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "HubberKit",
            path: "Sources/HubberKit"
        ),
        .testTarget(
            name: "HubberTests",
            dependencies: ["Hubber"],
            path: "Tests/HubberTests"
        ),
        .testTarget(
            name: "HubberKitTests",
            dependencies: ["HubberKit"],
            path: "Tests/HubberKitTests"
        ),
    ]
)
