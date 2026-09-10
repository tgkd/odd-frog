import Foundation
import OddFrogPluginAPI

@MainActor public final class DocumentSession {
    public let pluginID: String
    public let pluginName: String
    public let viewID: String
    public let result: PluginResult
    public let save: PluginAction
    public private(set) var title: String
    public private(set) var text: String
    public private(set) var revision = 0
    public private(set) var savedRevision = 0
    public private(set) var inFlight: Int?
    public private(set) var invalidated = false
    public private(set) var error: String?

    public init(view: PluginView, save: PluginAction, result: PluginResult, pluginName: String) {
        pluginID = result.pluginID
        self.pluginName = pluginName
        viewID = view.id
        self.result = result
        self.save = save
        title = view.title
        text = view.text
    }

    public var isDirty: Bool { revision != savedRevision }
    public var canSave: Bool { isDirty && inFlight == nil && !invalidated }

    public func edit(_ text: String) {
        guard text != self.text else { return }
        self.text = text
        revision += 1
        if !invalidated { error = nil }
    }

    public func beginSave() -> (revision: Int, text: String)? {
        guard canSave else { return nil }
        inFlight = revision
        return (revision, text)
    }

    public func acknowledge(revision: Int, title: String?) {
        guard inFlight == revision else { return }
        inFlight = nil
        savedRevision = revision
        if let title { self.title = title }
        error = nil
    }

    public func fail(revision: Int, message: String, terminal: Bool) {
        guard inFlight == revision else { return }
        inFlight = nil
        error = message
        invalidated = terminal
    }

    public func invalidate(message: String) {
        invalidated = true
        error = message
        inFlight = nil
    }
}
