// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniOpsKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MiniOpsKit",
            targets: ["MiniOpsKit"]
        ),
    ],
    targets: [
        .target(
            name: "MiniOpsKit",
            linkerSettings: [
                .linkedFramework("Network"),
            ]
        ),
    ]
)
