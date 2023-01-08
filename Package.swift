// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "switcheroo",
    platforms: [
        .macOS(.v11)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .target(name: "_switcheroo", dependencies: []),
        .executableTarget(name: "switcheroo", dependencies: ["_switcheroo", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "switcherooTests", dependencies: ["switcheroo"])
    ]
)
