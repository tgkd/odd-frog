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
        .target(name: "CalendarPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Calendar/Sources/CalendarPluginCore"),
        .executableTarget(name: "OddFrogCalendar", dependencies: ["CalendarPluginCore", "OddFrogPluginAPI"], path: "Plugins/Calendar/Sources/OddFrogCalendar"),
        .target(name: "RemindersPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Reminders/Sources/RemindersPluginCore"),
        .executableTarget(name: "OddFrogReminders", dependencies: ["RemindersPluginCore", "OddFrogPluginAPI"], path: "Plugins/Reminders/Sources/OddFrogReminders"),
        .target(
            name: "OddFrogCore",
            dependencies: ["OddFrogPluginAPI", .product(name: "TOMLKit", package: "TOMLKit")]
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
        .testTarget(name: "CalendarPluginTests", dependencies: ["CalendarPluginCore", "OddFrogPluginAPI"], path: "Plugins/Calendar/Tests"),
        .testTarget(name: "RemindersPluginTests", dependencies: ["RemindersPluginCore", "OddFrogPluginAPI"], path: "Plugins/Reminders/Tests"),
    ]
)
