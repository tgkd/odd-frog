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
        .target(name: "LLMClient", dependencies: ["OddFrogPluginAPI"]),
        .executableTarget(name: "OddFrogPackage", dependencies: ["OddFrogCore"]),
        .executableTarget(name: "OddFrogDevProvider", dependencies: ["OddFrogBuiltins", "OddFrogCore", "OddFrogPluginAPI"]),
        .target(name: "OddFrogHostServicesAPI"),
        .target(name: "BundledFeatures", dependencies: ["OddFrogCore", "OddFrogPluginAPI"], path: "Plugins/Shared/Sources/BundledFeatures"),
        .target(name: "CalendarPluginCore", dependencies: ["OddFrogPluginAPI", "OddFrogHostServicesAPI"], path: "Plugins/Calendar/Sources/CalendarPluginCore"),
        .target(name: "RemindersPluginCore", dependencies: ["OddFrogPluginAPI", "OddFrogHostServicesAPI"], path: "Plugins/Reminders/Sources/RemindersPluginCore"),
        .target(name: "NotesPluginCore", dependencies: ["OddFrogPluginAPI", "OddFrogHostServicesAPI"], path: "Plugins/Notes/Sources/NotesPluginCore"),
        .target(name: "ChatPluginCore", dependencies: ["OddFrogPluginAPI", "OddFrogHostServicesAPI", "LLMClient"], path: "Plugins/Chat/Sources/ChatPluginCore"),
        .target(name: "ClipboardPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Clipboard/Sources/ClipboardPluginCore"),
        .target(name: "CharactersPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Characters/Sources/CharactersPluginCore"),
        .target(name: "FilesPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Files/Sources/FilesPluginCore"),
        .target(name: "TranslatePluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Translate/Sources/TranslatePluginCore"),
        .target(name: "DicePluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Dice/Sources/DicePluginCore"),
        .target(name: "WorkflowsPluginCore", dependencies: ["OddFrogPluginAPI", .product(name: "TOMLKit", package: "TOMLKit")], path: "Plugins/Workflows/Sources/WorkflowsPluginCore"),
        .target(name: "OddFrogBuiltins", dependencies: ["BundledFeatures", "CalendarPluginCore", "RemindersPluginCore", "NotesPluginCore", "ChatPluginCore", "ClipboardPluginCore", "CharactersPluginCore", "FilesPluginCore", "TranslatePluginCore", "DicePluginCore", "WorkflowsPluginCore", "OddFrogCore", "OddFrogPluginAPI"]),
        .target(
            name: "OddFrogCore",
            dependencies: ["OddFrogPluginAPI", "OddFrogHostServicesAPI", .product(name: "TOMLKit", package: "TOMLKit")]
        ),
        .executableTarget(
            name: "OddFrog",
            dependencies: ["OddFrogCore", "OddFrogHostServicesAPI", "OddFrogBuiltins"]
        ),
        .testTarget(name: "BundledFeatureTests", dependencies: ["BundledFeatures", "OddFrogCore"], path: "Plugins/Shared/Tests", resources: [.copy("Fixtures")]),
        .testTarget(
            name: "OddFrogCoreTests",
            dependencies: ["OddFrogCore", "OddFrogHostServicesAPI", "BundledFeatures", "OddFrogBuiltins", "ClipboardPluginCore", "FilesPluginCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "CalendarPluginTests", dependencies: ["CalendarPluginCore", "OddFrogPluginAPI"], path: "Plugins/Calendar/Tests"),
        .testTarget(name: "RemindersPluginTests", dependencies: ["RemindersPluginCore", "OddFrogPluginAPI"], path: "Plugins/Reminders/Tests"),
        .testTarget(name: "NotesPluginTests", dependencies: ["NotesPluginCore", "OddFrogPluginAPI", "OddFrogCore"], path: "Plugins/Notes/Tests"),
        .testTarget(name: "ChatPluginTests", dependencies: ["ChatPluginCore", "LLMClient", "OddFrogPluginAPI", "OddFrogHostServicesAPI"], path: "Plugins/Chat/Tests"),
        .testTarget(name: "FilesPluginTests", dependencies: ["FilesPluginCore", "OddFrogPluginAPI"], path: "Plugins/Files/Tests"),
        .testTarget(name: "CharactersPluginTests", dependencies: ["CharactersPluginCore", "OddFrogPluginAPI"], path: "Plugins/Characters/Tests"),
        .testTarget(name: "ClipboardPluginTests", dependencies: ["ClipboardPluginCore", "OddFrogPluginAPI"], path: "Plugins/Clipboard/Tests"),
        .testTarget(name: "TranslatePluginTests", dependencies: ["TranslatePluginCore", "OddFrogPluginAPI"], path: "Plugins/Translate/Tests"),
        .testTarget(name: "DicePluginTests", dependencies: ["DicePluginCore", "OddFrogPluginAPI"], path: "Plugins/Dice/Tests"),
        .testTarget(name: "WorkflowsPluginTests", dependencies: ["WorkflowsPluginCore", "OddFrogPluginAPI"], path: "Plugins/Workflows/Tests"),
        .testTarget(name: "LLMClientTests", dependencies: ["LLMClient", "OddFrogPluginAPI"]),
    ]
)
