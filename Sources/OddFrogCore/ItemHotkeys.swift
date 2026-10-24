import Foundation

public enum ItemHotkeys {
    public struct Resolution: Equatable, Sendable {
        public var assigned: [String: Hotkey] = [:]
        public var conflicts: [String: String] = [:]
        /// What each item asked for, as written in settings or config, keyed like `assigned` and `conflicts`.
        public var requested: [String: String] = [:]
        public init(assigned: [String: Hotkey] = [:], conflicts: [String: String] = [:], requested: [String: String] = [:]) {
            self.assigned = assigned
            self.conflicts = conflicts
            self.requested = requested
        }
    }

    /// Hands each hotkey to the first enabled item (in `items` order) that asks for it. An item asks
    /// through its override in `settings`, or failing that through `defaults` (hotkeys declared in
    /// config). `reserved` maps hotkeys the launcher and plugins already hold to their owner's name;
    /// an item asking for one of those, a hotkey another item took, or an unparsable hotkey gets a
    /// conflict message instead. `retaining` names items (id to title) that are missing from `items`
    /// but still hold a hotkey: catalogs empty and refill on every plugin reload, and a hotkey should
    /// not drop out in between.
    public static func resolve(items: [LauncherItem], retaining: [String: String] = [:], settings: Settings,
                               defaults: [String: Hotkey] = [:], reserved: [Hotkey: String] = [:]) -> Resolution {
        var resolution = Resolution()
        var owners = reserved
        let overrides = Dictionary(settings.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Holders that are only retained come first, so a catalog refilling in pieces cannot move a hotkey.
        let present = Set(items.map(\.id))
        let candidates = retaining.filter { !present.contains($0.key) }.sorted { $0.key < $1.key }.map { (id: $0.key, title: $0.value) }
            + items.map { (id: $0.id, title: $0.title) }
        for item in candidates {
            let override = overrides[item.id]
            if override?.enabled == false { continue }
            let hotkey: Hotkey
            if let override, let raw = override.hotkey {
                resolution.requested[item.id] = raw
                do {
                    guard let parsed = try override.parsedHotkey() else { continue }
                    hotkey = parsed
                } catch {
                    resolution.conflicts[item.id] = "\(error)"
                    continue
                }
            } else if let fallback = defaults[item.id] {
                resolution.requested[item.id] = fallback.serialized
                hotkey = fallback
            } else {
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
