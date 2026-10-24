import Foundation

public enum ItemHotkeys {
    public struct Resolution: Equatable, Sendable {
        public var assigned: [String: Hotkey] = [:]
        public var conflicts: [String: String] = [:]
        public init(assigned: [String: Hotkey] = [:], conflicts: [String: String] = [:]) {
            self.assigned = assigned
            self.conflicts = conflicts
        }
    }

    /// The hotkey text each enabled item asks for, keyed by item id: its override in `settings`, or
    /// failing that its entry in `defaults` (hotkeys declared in config). Disabled items ask for nothing.
    public static func requests(settings: Settings, defaults: [String: Hotkey]) -> [String: String] {
        var requests = defaults.mapValues(\.serialized)
        for override in settings.items {
            if !override.enabled {
                requests[override.id] = nil
            } else if let raw = override.hotkey {
                requests[override.id] = raw
            }
        }
        return requests
    }

    /// Hands each hotkey to the first item in `items` that asks for it. Items in `holding` go first, so
    /// a rebuilt catalog in a different order never moves a hotkey away from the item that has it.
    /// `reserved` maps hotkeys the launcher and plugins already hold to their owner's name; an item
    /// asking for one of those, a hotkey another item took, or an unparsable hotkey gets a conflict
    /// message instead.
    public static func resolve(items: [LauncherItem], holding: Set<String> = [], settings: Settings,
                               defaults: [String: Hotkey] = [:], reserved: [Hotkey: String] = [:]) -> Resolution {
        var resolution = Resolution()
        var owners = reserved
        let requests = requests(settings: settings, defaults: defaults)
        guard !requests.isEmpty else { return resolution }
        for item in items.filter({ holding.contains($0.id) }) + items.filter({ !holding.contains($0.id) }) {
            guard let raw = requests[item.id] else { continue }
            let hotkey: Hotkey
            do {
                hotkey = try Hotkey.parse(raw)
            } catch {
                resolution.conflicts[item.id] = "Invalid hotkey '\(raw)': \(error)."
                continue
            }
            if let owner = owners[hotkey] {
                resolution.conflicts[item.id] = "Hotkey \(hotkey.description) is already used by \(owner)."
            } else {
                owners[hotkey] = item.title
                resolution.assigned[item.id] = hotkey
            }
        }
        return resolution
    }
}
