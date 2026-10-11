// swift-tools-version: 6.0
// Pebble — a native Swift + Metal block-survival game for macOS and iOS.
// macOS is CLI-only: swift build -c release. No .xcodeproj. The iOS app is an
// XcodeGen project in ios/ that links the PebbleApp library from here.

import PackageDescription

let package = Package(
    name: "Pebble",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PebbleCore", targets: ["PebbleCore"]),
        .library(name: "PebbleApp", targets: ["PebbleApp"]),
    ],
    targets: [
        // the engine: headless-testable, no AppKit dependencies
        .target(
            name: "PebbleCore",
            path: "Sources/PebbleCore",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        // the shared app stack: renderer, UI, screens, HUD, audio, input
        // routing — no AppKit/UIKit, so both shells link it
        .target(
            name: "PebbleApp",
            dependencies: ["PebbleCore"],
            path: "Sources/PebbleApp",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        // the macOS app: AppKit window + MTKView shell around PebbleApp
        .executableTarget(
            name: "Pebble",
            dependencies: ["PebbleApp"],
            path: "Sources/Pebble",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        // headless smoke tests against the frozen golden baselines
        .executableTarget(
            name: "pebsmoke",
            dependencies: ["PebbleCore"],
            path: "Sources/pebsmoke",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
