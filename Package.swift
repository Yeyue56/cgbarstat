// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CGBarStat",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CGBarStatCore", targets: ["CGBarStatCore"]),
        .executable(name: "CGBarStatApp", targets: ["CGBarStatApp"]),
    ],
    targets: [
        .target(name: "CGBarStatCore"),
        .executableTarget(
            name: "CGBarStatApp",
            dependencies: ["CGBarStatCore"]
        ),
        .testTarget(
            name: "CGBarStatCoreTests",
            dependencies: ["CGBarStatCore"]
        ),
    ]
)
