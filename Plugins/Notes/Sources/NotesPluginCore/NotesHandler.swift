import Foundation
import OddFrogHostServicesAPI
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
            return try .encode(NotesProvider.respond(to: query, notes: await notes(for: query, operation: operation)))
        case "activate":
            let activation = try params["input"].decode(PluginActivation.self)
            return try .encode(await effects(for: activation, operation: operation))
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }
    private func notes(for query: PluginQuery, operation: ProviderOperation) async throws -> [Note] {
        let filter = String(query.query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let limit = max(1, min(query.maxResults, 50))
        let snapshot = try await operation.service("notes.read@1", params: .encode(NotesQuery(query: filter, limit: limit)))
            .decode(NotesSnapshot.self)
        return snapshot.notes.map(Note.init)
    }
    private func note(_ id: String, operation: ProviderOperation) async throws -> Note {
        Note(try await operation.service("notes.get@1", params: .object(["id": .string(id)])).decode(NoteRecord.self))
    }
    private func effects(for activation: PluginActivation, operation: ProviderOperation) async throws -> PluginEffects {
        switch activation.actionID {
        case "open":
            guard let id = activation.payload["id"].string else {
                throw RPCError("params", "A note ID is required.")
            }
            return PluginEffects(view: NotesProvider.view(for: try await note(id, operation: operation)))
        case "create":
            let id = UUID().uuidString.lowercased()
            drafts.insert(id)
            let text = activation.payload["text"].string ?? ""
            return PluginEffects(view: NotesProvider.view(for: Note(id: id, text: text, modified: Date())))
        case "save":
            guard let id = activation.payload["id"].string else {
                throw RPCError("params", "A note ID is required.")
            }
            let text = activation.text ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, drafts.contains(id),
               (try? await note(id, operation: operation)) == nil {
                return PluginEffects(view: NotesProvider.view(for: Note(id: id, text: text, modified: Date())))
            }
            let saved = try await operation.service("notes.write@1", params: .encode(NoteWrite(id: id, text: text)))
                .decode(NoteRecord.self)
            drafts.remove(id)
            return PluginEffects(refreshQuery: true, view: NotesProvider.view(for: Note(saved)))
        default:
            throw RPCError("action", "Unknown action: \(activation.actionID)")
        }
    }
}
