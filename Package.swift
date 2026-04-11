// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "eta",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ProcessProgress", targets: ["ProcessProgress"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "ProcessProgress"),
        .executableTarget(
            name: "eta",
            dependencies: [
                "ProcessProgress",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/eta-cli"
        ),
    ]
)
