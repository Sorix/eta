// swift-tools-version: 6.0

import PackageDescription

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
]

var processProgressDependencies: [Target.Dependency] = []

#if os(Linux)
dependencies.append(.package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"))
processProgressDependencies.append(.product(name: "Crypto", package: "swift-crypto"))
#endif

let package = Package(
    name: "eta",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ProcessProgress", targets: ["ProcessProgress"]),
    ],
    dependencies: dependencies,
    targets: [
        .target(
            name: "ProcessProgress",
            dependencies: processProgressDependencies
        ),
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
        .testTarget(
            name: "ProcessProgressTests",
            dependencies: ["ProcessProgress"]
        ),
        .testTarget(
            name: "EtaCLITests",
            dependencies: [
                "EtaCLI",
                "ProcessProgress",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
