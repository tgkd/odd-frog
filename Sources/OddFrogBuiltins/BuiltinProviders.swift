import Foundation
import AppKit
import BundledFeatures
import CalendarPluginCore
import RemindersPluginCore
import NotesPluginCore
import ChatPluginCore
import ClipboardPluginCore
import CharactersPluginCore
import FilesPluginCore
import TranslatePluginCore
import OddFrogCore
import OddFrogPluginAPI

public enum BuiltinProviders {
    public static let clipboardArchive = ClipboardArchive()
    public static let factories: [String: PluginCoordinator.BuiltinProviderFactory] = [
        "applications": { FeatureProvider(.applications) },
        "commands": { FeatureProvider(.commands) },
        "scripts": { FeatureProvider(.scripts) },
        "calculator": { FeatureProvider(.calculator) },
        "web": { FeatureProvider(.web) },
        "terminal": { FeatureProvider(.terminal) },
        "calendar": { CalendarHandler() },
        "reminders": { RemindersHandler() },
        "notes": { NotesHandler() },
        "chat": { ChatHandler() },
        "clipboard": { ClipboardHandler(archive: clipboardArchive, pasteboard: ClipboardPasteboard(name: .general)) },
        "files": { FilesHandler() },
        "emoji": { CharactersHandler(.emoji) },
        "symbols": { CharactersHandler(.symbols) },
        "translate": { TranslateHandler() },
    ]
}
