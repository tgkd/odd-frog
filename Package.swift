// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OddFrog",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "OddFrogCore",
            dependencies: [.product(name: "TOMLKit", package: "TOMLKit")]
        ),
        .executableTarget(
            name: "OddFrog",
            dependencies: ["OddFrogCore"]
        ),
        .testTarget(
            name: "OddFrogCoreTests",
            dependencies: ["OddFrogCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
