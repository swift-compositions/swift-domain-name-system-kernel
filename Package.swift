// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-domain-name-system-kernel",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(
            name: "Domain Name System Kernel",
            targets: ["Domain Name System Kernel"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-foundations/swift-domain-name-system.git",
            branch: "main"
        ),
        .package(url: "https://github.com/swift-foundations/swift-ip-address.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-threads.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-kernel.git", branch: "main"),
        .package(
            url: "https://github.com/swift-primitives/swift-either-primitives.git",
            branch: "main"
        ),
    ],
    targets: [
        .target(
            name: "Domain Name System Kernel",
            dependencies: [
                .product(name: "Domain Name System", package: "swift-domain-name-system"),
                .product(name: "IP Address", package: "swift-ip-address"),
                .product(name: "Thread Pool", package: "swift-threads"),
                .product(name: "Kernel", package: "swift-kernel"),
                .product(name: "Either Primitives", package: "swift-either-primitives"),
            ]
        ),
        .testTarget(
            name: "Domain Name System Kernel Tests",
            dependencies: [
                "Domain Name System Kernel",
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
