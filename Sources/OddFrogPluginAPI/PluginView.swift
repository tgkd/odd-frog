import Foundation

public struct PluginView: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case editor }
    public var kind: Kind
    public var id: String
    public var title: String
    public var text: String
    public var placeholder: String?
    public var save: PluginAction
    public init(kind: Kind = .editor, id: String, title: String, text: String = "",
                placeholder: String? = nil, save: PluginAction) {
        self.kind = kind; self.id = id; self.title = title; self.text = text
        self.placeholder = placeholder; self.save = save
    }
}
