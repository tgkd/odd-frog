// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OddFrog",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
    ],
    targets: [
        .target(name: "OddFrogPluginAPI"),
        .executableTarget(name: "OddFrogPackage", dependencies: ["OddFrogCore"]),
        .target(name: "OddFrogHostServicesAPI"),
        .target(name: "BundledFeatures", dependencies: ["OddFrogCore", "OddFrogPluginAPI"], path: "Plugins/Shared/Sources/BundledFeatures"),
        .target(name: "CalendarPluginCore", dependencies: ["OddFrogPluginAPI", "OddFrogHostServicesAPI"], path: "Plugins/Calendar/Sources/CalendarPluginCore"),
        .target(name: "RemindersPluginCore", dependencies: ["OddFrogPluginAPI", "OddFrogHostServicesAPI"], path: "Plugins/Reminders/Sources/RemindersPluginCore"),
        .target(name: "OddFrogBuiltins", dependencies: ["BundledFeatures", "CalendarPluginCore", "RemindersPluginCore", "OddFrogCore", "OddFrogPluginAPI"]),
        .target(
            name: "OddFrogCore",
            dependencies: ["OddFrogPluginAPI", .product(name: "TOMLKit", package: "TOMLKit")]
        ),
        .executableTarget(
            name: "OddFrog",
            dependencies: ["OddFrogCore", "OddFrogHostServicesAPI", "OddFrogBuiltins"]
        ),
        .testTarget(name: "BundledFeatureTests", dependencies: ["BundledFeatures", "OddFrogCore"], path: "Plugins/Shared/Tests", resources: [.copy("Fixtures")]),
        .testTarget(
            name: "OddFrogCoreTests",
            dependencies: ["OddFrogCore", "OddFrogHostServicesAPI", "BundledFeatures", "OddFrogBuiltins"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "CalendarPluginTests", dependencies: ["CalendarPluginCore", "OddFrogPluginAPI"], path: "Plugins/Calendar/Tests"),
        .testTarget(name: "RemindersPluginTests", dependencies: ["RemindersPluginCore", "OddFrogPluginAPI"], path: "Plugins/Reminders/Tests"),
    ]
)
