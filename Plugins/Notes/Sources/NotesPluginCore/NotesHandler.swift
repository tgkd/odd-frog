import Foundation
import OddFrogPluginAPI

public actor NotesHandler: ProviderHandler {
    private var drafts = Set<String>()
    public init() {}
    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        switch method {
        case "initialize":
            return .object(["apiVersion": .number(2)])
        case "settings":
            return .object([:])
        case "query":
            let query = try params["input"].decode(PluginQuery.self)
            return try .encode(NotesProvider.respond(to: query, notes: store(params).list()))
        case "activate":
            let activation = try params["input"].decode(PluginActivation.self)
            return try .encode(effects(for: activation, store: store(params)))
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }
    private func store(_ params: JSONValue) throws -> NoteStore {
        let context = try params["context"].decode(PluginContext.self)
        return NoteStore(directory: URL(fileURLWithPath: context.storagePath))
    }
    private func effects(for activation: PluginActivation, store: NoteStore) throws -> PluginEffects {
        switch activation.actionID {
        case "open":
            guard let id = activation.payload["id"].string else {
                throw RPCError("params", "A note ID is required.")
            }
            return PluginEffects(view: NotesProvider.view(for: try store.read(id: id)))
        case "create":
            let id = store.newID()
            drafts.insert(id)
            let text = activation.payload["text"].string ?? ""
            return PluginEffects(view: NotesProvider.view(for: Note(id: id, text: text, modified: Date())))
        case "save":
            guard let id = activation.payload["id"].string else {
                throw RPCError("params", "A note ID is required.")
            }
            let text = activation.text ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, drafts.contains(id),
               try !store.exists(id: id) {
                return PluginEffects(view: NotesProvider.view(for: Note(id: id, text: text, modified: Date())))
            }
            let saved = try store.write(id: id, text: text)
            drafts.remove(id)
            return PluginEffects(refreshQuery: true, view: NotesProvider.view(for: saved))
        default:
            throw RPCError("action", "Unknown action: \(activation.actionID)")
        }
    }
}
