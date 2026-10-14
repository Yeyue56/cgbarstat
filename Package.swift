// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stipend",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StipendCore", targets: ["StipendCore"]),
        .executable(name: "StipendApp", targets: ["StipendApp"]),
    ],
    targets: [
        .target(name: "StipendCore"),
        .executableTarget(
            name: "StipendApp",
            dependencies: ["StipendCore"]
        ),
        .testTarget(
            name: "StipendCoreTests",
            dependencies: ["StipendCore"]
        ),
    ]
)
