// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ConstellationBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ConstellationBar", targets: ["ConstellationBar"])
    ],
    targets: [
        .executableTarget(
            name: "ConstellationBar",
            path: "Sources/ConstellationBar"
        ),
        .testTarget(name: "ConstellationBarTests", dependencies: ["ConstellationBar"])
    ]
)
