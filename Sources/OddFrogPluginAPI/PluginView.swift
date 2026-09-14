import Foundation

public struct PluginMessage: Codable, Sendable, Hashable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var id: String
    public var role: Role
    public var text: String
    public init(id: String, role: Role, text: String) {
        self.id = id; self.role = role; self.text = text
    }
}

public struct PluginMessageDelta: Codable, Sendable, Hashable {
    public var viewID: String
    public var messageID: String
    public var delta: String
    public init(viewID: String, messageID: String, delta: String) {
        self.viewID = viewID; self.messageID = messageID; self.delta = delta
    }
}

public struct PluginView: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case editor, chat, month }
    public var kind: Kind
    public var id: String
    public var title: String
    public var text: String
    public var placeholder: String?
    public var save: PluginAction?
    public var messages: [PluginMessage]?
    public var prompt: String?
    public var send: PluginAction?
    public init(kind: Kind = .editor, id: String, title: String, text: String = "",
                placeholder: String? = nil, save: PluginAction) {
        self.kind = kind; self.id = id; self.title = title; self.text = text
        self.placeholder = placeholder; self.save = save
    }
    public init(id: String, title: String, messages: [PluginMessage], placeholder: String? = nil,
                prompt: String? = nil, send: PluginAction) {
        kind = .chat; self.id = id; self.title = title; text = ""
        self.placeholder = placeholder; self.messages = messages; self.prompt = prompt; self.send = send
    }
    public init(month id: String, title: String) {
        kind = .month; self.id = id; self.title = title; text = ""
    }
    enum CodingKeys: String, CodingKey { case kind, id, title, text, placeholder, save, messages, prompt, send }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        save = try c.decodeIfPresent(PluginAction.self, forKey: .save)
        messages = try c.decodeIfPresent([PluginMessage].self, forKey: .messages)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        send = try c.decodeIfPresent(PluginAction.self, forKey: .send)
    }
}
