// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZenSTOMP",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(name: "ZenSTOMP", targets: ["ZenSTOMP"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.94.1"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.36.0"),
    ],
    targets: [
        .target(
            name: "ZenSTOMP",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        .testTarget(
            name: "ZenSTOMPTests",
            dependencies: ["ZenSTOMP"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
