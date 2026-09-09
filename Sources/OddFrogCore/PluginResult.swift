import Foundation
import OddFrogPluginAPI

public struct PluginResult: Sendable, Hashable {
    public let pluginID: String
    public var item: PluginItem
    public let generation: UUID
    public let catalog: Bool
    public let directory: URL?
    public var id: String { "plugin:\(pluginID):\(item.id)" }
    public var historyEligible: Bool { catalog && item.history == true }
    public init(pluginID: String, item: PluginItem, generation: UUID = UUID(), catalog: Bool = false, directory: URL? = nil) {
        self.pluginID = pluginID; self.item = item; self.generation = generation; self.catalog = catalog; self.directory = directory
    }
}
