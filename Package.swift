// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniOps",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "miniopsd",
            targets: ["miniopsd"]
        ),
    ],
    dependencies: [
        .package(path: "Packages/MiniOpsKit"),
    ],
    targets: [
        .executableTarget(
            name: "miniopsd",
            dependencies: [
                .product(name: "MiniOpsKit", package: "MiniOpsKit"),
            ],
            path: "Sources/miniopsd"
        ),
    ]
)
