import Foundation
import BundledFeatures
import CalendarPluginCore
import RemindersPluginCore
import OddFrogCore
import OddFrogPluginAPI

public enum BuiltinProviders {
    public static let factories: [String: PluginCoordinator.BuiltinProviderFactory] = [
        "applications": { FeatureProvider(.applications) },
        "commands": { FeatureProvider(.commands) },
        "scripts": { FeatureProvider(.scripts) },
        "calculator": { FeatureProvider(.calculator) },
        "web": { FeatureProvider(.web) },
        "terminal": { FeatureProvider(.terminal) },
        "calendar": { CalendarHandler() },
        "reminders": { RemindersHandler() },
    ]
}
