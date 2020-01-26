// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZenSTOMP",
    products: [
        .library(
            name: "ZenSTOMP",
            targets: ["ZenSTOMP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git",
                 from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git",
                 from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "ZenSTOMP",
            dependencies: [
                "NIO",
                "NIOHTTP1",
                "NIOWebSocket",
                "NIOSSL"
            ]
        ),
        .testTarget(
            name: "ZenSTOMPTests",
            dependencies: ["ZenSTOMP"]),
    ]
)
