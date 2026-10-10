// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    // Swift 6.2+ approachable concurrency: nonisolated async functions run on the caller's actor
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "LenKit",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LenKit", targets: ["LenKit"]),
    ],
    targets: [
        .target(name: "LenKit", swiftSettings: swiftSettings),
        .testTarget(
            name: "LenKitTests",
            dependencies: ["LenKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
