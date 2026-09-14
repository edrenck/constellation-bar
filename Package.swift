// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ConstellationBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ConstellationBar", targets: ["ConstellationBar"]),
        .library(name: "NativeMediaHelper", type: .dynamic, targets: ["NativeMediaHelper"])
    ],
    targets: [
        .target(name: "NativeMediaHelper", path: "Sources/NativeMediaHelper",
                cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ImageIO")]),
        .executableTarget(
            name: "ConstellationBar",
            path: "Sources/ConstellationBar"
        ),
        .testTarget(name: "ConstellationBarTests", dependencies: ["ConstellationBar"])
    ]
)
