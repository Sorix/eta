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
        .target(
            name: "EtaCLI",
            dependencies: [
                "ProcessProgress",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/EtaCLI"
        ),
        .executableTarget(
            name: "eta",
            dependencies: ["EtaCLI"],
            path: "Sources/eta-cli"
        ),
    ]
)
