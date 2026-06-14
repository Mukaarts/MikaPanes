// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MikaPanes",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MikaPanes",
            path: "Sources/MikaPanes",
            swiftSettings: [
                // MVP: keep Swift 5 language mode to avoid strict-concurrency friction
                // with the heavily @MainActor AppKit/AX/Carbon code. Revisit later.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "MikaPanesTests",
            dependencies: ["MikaPanes"],
            path: "Tests/MikaPanesTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
