import Foundation

public enum PluginHotkeys {
    public struct Resolution: Equatable, Sendable {
        public var assigned: [String: Hotkey] = [:]
        public var conflicts: [String: String] = [:]
    }

    /// Hands each hotkey to the first package (in `packages` order) that asks for it. Later
    /// packages with the same hotkey, and any package asking for `reserved`, get a conflict
    /// message instead. Packages that are disabled, failed, or whose override is invalid are skipped.
    public static func resolve(packages: [PluginPackage], settings: [PluginSetting],
                               failures: Set<String> = [], reserved: Hotkey? = nil,
                               reservedName: String = "the launcher") -> Resolution {
        var resolution = Resolution()
        var owners: [Hotkey: String] = [:]
        for package in packages {
            let id = package.manifest.id
            guard package.isEnabled(settings: settings), !failures.contains(id),
                  let hotkey = try? package.hotkey(in: settings) else { continue }
            if hotkey == reserved {
                resolution.conflicts[id] = "Hotkey \(hotkey.description) is used by \(reservedName)."
            } else if let owner = owners[hotkey] {
                resolution.conflicts[id] = "Hotkey \(hotkey.description) is also used by \(owner)."
            } else {
                owners[hotkey] = package.manifest.name
                resolution.assigned[id] = hotkey
            }
        }
        return resolution
    }
}
