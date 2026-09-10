import Foundation
import OddFrogPluginAPI

@MainActor public final class ChatSession {
    public struct Outgoing {
        public let id: Int
        public let text: String
        public let userID: String
        public var replyID: String
    }

    public let pluginID: String
    public let pluginName: String
    public let viewID: String
    public let result: PluginResult
    public let send: PluginAction
    public let placeholder: String?
    public private(set) var title: String
    public private(set) var messages: [PluginMessage]
    public private(set) var draft = ""
    public private(set) var outgoing: Outgoing?
    public private(set) var invalidated = false
    public private(set) var error: String?
    private var serial = 0

    public init(view: PluginView, send: PluginAction, result: PluginResult, pluginName: String) {
        pluginID = result.pluginID
        self.pluginName = pluginName
        viewID = view.id
        self.result = result
        self.send = send
        placeholder = view.placeholder
        title = view.title
        messages = view.messages ?? []
        draft = view.prompt ?? ""
    }

    public var isSending: Bool { outgoing != nil }
    public var canSend: Bool {
        !invalidated && outgoing == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func edit(_ draft: String) {
        self.draft = draft
        error = nil
    }

    public func beginSend() -> Outgoing? {
        guard canSend else {
            return nil
        }
        serial += 1
        let text = draft
        let userID = "host-user-\(serial)", replyID = "host-reply-\(serial)"
        messages.append(PluginMessage(id: userID, role: .user, text: text))
        messages.append(PluginMessage(id: replyID, role: .assistant, text: ""))
        let started = Outgoing(id: serial, text: text, userID: userID, replyID: replyID)
        outgoing = started
        draft = ""
        error = nil
        return started
    }

    public func receive(_ delta: PluginMessageDelta) -> Bool {
        guard var current = outgoing, delta.viewID == viewID else {
            return false
        }
        guard let index = messages.firstIndex(where: { $0.id == current.replyID }) else {
            return false
        }
        if current.replyID != delta.messageID {
            current.replyID = delta.messageID
            outgoing = current
            messages[index].id = delta.messageID
        }
        messages[index].text += delta.delta
        return true
    }

    public func complete(id: Int, view: PluginView?) {
        guard outgoing?.id == id else {
            return
        }
        outgoing = nil
        guard let view else {
            return
        }
        messages = view.messages ?? []
        title = view.title
    }

    public func fail(id: Int, message: String, terminal: Bool) {
        guard let current = outgoing, current.id == id else {
            return
        }
        messages.removeAll { $0.id == current.userID || $0.id == current.replyID }
        draft = current.text
        error = message
        invalidated = terminal
        outgoing = nil
    }

    public func invalidate(message: String) {
        if let current = outgoing {
            fail(id: current.id, message: message, terminal: true)
            return
        }
        invalidated = true
        error = message
    }
}
