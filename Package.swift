// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stipend",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StipendCore", targets: ["StipendCore"]),
    ],
    targets: [
        .target(name: "StipendCore"),
        .testTarget(
            name: "StipendCoreTests",
            dependencies: ["StipendCore"]
        ),
    ]
)
