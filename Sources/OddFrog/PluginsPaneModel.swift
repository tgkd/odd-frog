import Foundation
import Observation
import OddFrogCore
import OddFrogPluginAPI

@Observable
@MainActor
final class PluginsPaneModel {
    private(set) var packages: [PluginPackage] = []
    private(set) var settings: [PluginSetting] = []
    private(set) var failures: [String: String] = [:]
    private(set) var errors: [String] = []
    private(set) var message: (package: String, text: String)?

    @ObservationIgnored var onToggle: ((String, Bool) -> Void)?
    @ObservationIgnored var onReload: (() -> Void)?
    @ObservationIgnored var onSetting: ((String, String, JSONValue) -> Void)?
    @ObservationIgnored var onTrigger: ((String, String?) -> Void)?
    @ObservationIgnored var onManageLinks: (() -> Void)?

    func update(packages: [PluginPackage], settings: [PluginSetting], failures: [String: String], errors: [String]) {
        guard packages != self.packages || settings != self.settings || failures != self.failures || errors != self.errors else { return }
        self.packages = packages
        self.settings = settings
        self.failures = failures
        self.errors = errors
        message = nil
    }

    func value(of definition: PluginSettingDefinition, in package: PluginPackage) -> JSONValue {
        package.setting(in: settings)?.values?[definition.key] ?? definition.defaultValue
    }

    func resolvedTrigger(of package: PluginPackage) -> String {
        (try? package.trigger(in: settings))?.text ?? package.manifest.trigger?.text ?? ""
    }

    func commit(_ value: JSONValue, for definition: PluginSettingDefinition, in package: PluginPackage) {
        do {
            try definition.validate(value)
            message = nil
            onSetting?(package.manifest.id, definition.key, value)
        } catch {
            message = (package.manifest.id, "\(package.manifest.name): \(error)")
        }
    }

    func commitTrigger(_ raw: String, for package: PluginPackage) {
        guard let trigger = package.manifest.trigger else { return }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .keyword = trigger { text = text.lowercased() }
        let stored = package.setting(in: settings)?.trigger
        let resolved = resolvedTrigger(of: package)
        if text.isEmpty || text == trigger.text {
            message = nil
            if stored != nil { onTrigger?(package.manifest.id, nil) }
            return
        }
        do {
            let candidate = try trigger.replacing(text)
            if let other = package.triggerConflict(candidate, among: packages, settings: settings) {
                message = (package.manifest.id, "\(package.manifest.name): \(trigger.label) '\(text)' is already used by \(other.manifest.name).")
                return
            }
            message = nil
            if text != resolved { onTrigger?(package.manifest.id, text) }
        } catch {
            message = (package.manifest.id, "\(package.manifest.name): \(error)")
        }
    }

    func addFolders(_ urls: [URL], for definition: PluginSettingDefinition, in package: PluginPackage) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var folders = (value(of: definition, in: package).array ?? []).compactMap(\.string)
        var seen = Set(folders)
        for url in urls {
            var path = url.path
            if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
            if seen.insert(path).inserted { folders.append(path) }
        }
        commit(.array(folders.map(JSONValue.string)), for: definition, in: package)
    }

    static func format(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }
}
