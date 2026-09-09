import Foundation
import OddFrogPluginAPI

public struct PluginResult: Sendable, Hashable {
    public let pluginID: String
    public let item: PluginItem
    public var id: String { "plugin:\(pluginID):\(item.id)" }

    public init(pluginID: String, item: PluginItem) { self.pluginID = pluginID; self.item = item }
}
