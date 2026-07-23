// swift-tools-version: 6.3.3

import PackageDescription

let package = Package(
    name: "swift-domain-name-system-iso-9945",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "Domain Name System ISO 9945",
            targets: ["Domain Name System ISO 9945"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swift-foundations/swift-domain-name-system.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-ip-address.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-threads.git", branch: "main"),
        .package(url: "https://github.com/swift-iso/swift-iso-9945.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-either-primitives.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Domain Name System ISO 9945",
            dependencies: [
                .product(name: "Domain Name System", package: "swift-domain-name-system"),
                .product(name: "IP Address", package: "swift-ip-address"),
                .product(name: "Thread Pool", package: "swift-threads"),
                .product(name: "ISO 9945 Kernel Socket Address", package: "swift-iso-9945"),
                .product(name: "Either Primitives", package: "swift-either-primitives"),
            ]
        ),
        .testTarget(
            name: "Domain Name System ISO 9945 Tests",
            dependencies: [
                "Domain Name System ISO 9945",
                .product(name: "Thread Gate", package: "swift-threads"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
