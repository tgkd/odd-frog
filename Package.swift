// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OddFrog",
    platforms: [.macOS(.v26)],
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
        .target(name: "NotesPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Notes/Sources/NotesPluginCore"),
        .target(name: "ChatPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Chat/Sources/ChatPluginCore"),
        .target(name: "ClipboardPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Clipboard/Sources/ClipboardPluginCore"),
        .target(name: "OddFrogBuiltins", dependencies: ["BundledFeatures", "CalendarPluginCore", "RemindersPluginCore", "NotesPluginCore", "ChatPluginCore", "ClipboardPluginCore", "OddFrogCore", "OddFrogPluginAPI"]),
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
            dependencies: ["OddFrogCore", "OddFrogHostServicesAPI", "BundledFeatures", "OddFrogBuiltins", "ClipboardPluginCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "CalendarPluginTests", dependencies: ["CalendarPluginCore", "OddFrogPluginAPI"], path: "Plugins/Calendar/Tests"),
        .testTarget(name: "RemindersPluginTests", dependencies: ["RemindersPluginCore", "OddFrogPluginAPI"], path: "Plugins/Reminders/Tests"),
        .testTarget(name: "NotesPluginTests", dependencies: ["NotesPluginCore", "OddFrogPluginAPI"], path: "Plugins/Notes/Tests"),
        .testTarget(name: "ChatPluginTests", dependencies: ["ChatPluginCore", "OddFrogPluginAPI"], path: "Plugins/Chat/Tests"),
        .testTarget(name: "ClipboardPluginTests", dependencies: ["ClipboardPluginCore", "OddFrogPluginAPI"], path: "Plugins/Clipboard/Tests"),
    ]
)
