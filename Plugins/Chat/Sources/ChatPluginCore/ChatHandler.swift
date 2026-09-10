import Foundation
import OddFrogPluginAPI

public actor ChatHandler: ProviderHandler {
    private let backend: any ChatBackend
    private var drafts = Set<String>()
    public init(backend: any ChatBackend = OpenAICompatibleBackend()) {
        self.backend = backend
    }
    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        switch method {
        case "initialize":
            return .object(["apiVersion": .number(2)])
        case "settings":
            return .object([:])
        case "query":
            let query = try params["input"].decode(PluginQuery.self)
            return try .encode(ChatProvider.respond(to: query, conversations: store(params).list()))
        case "activate":
            let activation = try params["input"].decode(PluginActivation.self)
            return try .encode(await effects(for: activation, params: params, operation: operation))
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }
    private func store(_ params: JSONValue) throws -> ConversationStore {
        let context = try params["context"].decode(PluginContext.self)
        return ConversationStore(directory: URL(fileURLWithPath: context.storagePath))
    }
    private func effects(for activation: PluginActivation, params: JSONValue,
                         operation: ProviderOperation) async throws -> PluginEffects {
        let store = try store(params)
        switch activation.actionID {
        case "open":
            return PluginEffects(view: ChatProvider.view(for: try store.read(id: try identifier(activation))))
        case "create":
            let id = store.newID()
            drafts.insert(id)
            let now = Date()
            let conversation = Conversation(id: id, title: "New chat", created: now, modified: now, messages: [])
            return PluginEffects(view: ChatProvider.view(for: conversation, prompt: activation.payload["text"].string))
        case "send":
            return try await send(activation, params: params, store: store, operation: operation)
        case "delete":
            let id = try identifier(activation)
            try store.delete(id: id)
            drafts.remove(id)
            return PluginEffects(notification: "Conversation deleted.", refreshQuery: true)
        default:
            throw RPCError("action", "Unknown action: \(activation.actionID)")
        }
    }
    private func send(_ activation: PluginActivation, params: JSONValue, store: ConversationStore,
                      operation: ProviderOperation) async throws -> PluginEffects {
        let id = try identifier(activation)
        let text = (activation.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw RPCError("params", "Nothing to send.")
        }
        let draft = drafts.contains(id)
        let now = Date()
        var conversation = draft
            ? Conversation(id: id, title: "New chat", created: now, modified: now, messages: [])
            : try store.read(id: id)
        let settings = try params["context"].decode(PluginContext.self).settings
        guard let baseURL = URL(string: (settings["base_url"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)),
              baseURL.scheme?.isEmpty == false, baseURL.host?.isEmpty == false else {
            throw RPCError("chat", "Set a valid API base URL in Chat settings.")
        }
        let model = (settings["model"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw RPCError("chat", "Set a model name in Chat settings.")
        }
        conversation.messages.append(PluginMessage(id: store.newID(), role: .user, text: text))
        let request = ChatRequest(baseURL: baseURL,
                                  apiKey: (settings["api_key"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                  model: model, systemPrompt: settings["system_prompt"]?.string ?? "",
                                  messages: conversation.messages)
        let replyID = store.newID()
        var reply = ""
        for try await chunk in try await backend.stream(request) {
            try Task.checkCancellation()
            reply += chunk
            try await operation.emit("messageDelta", params: .encode(
                PluginMessageDelta(viewID: id, messageID: replyID, delta: chunk)))
        }
        guard !reply.isEmpty else {
            throw RPCError("chat", "The model returned no text.")
        }
        conversation.messages.append(PluginMessage(id: replyID, role: .assistant, text: reply))
        if draft || conversation.title == "New chat" {
            conversation.title = Conversation.title(from: conversation.messages.first { $0.role == .user }?.text ?? text)
        }
        conversation.modified = Date()
        try store.write(conversation)
        drafts.remove(id)
        return PluginEffects(refreshQuery: true, view: ChatProvider.view(for: conversation))
    }
    private func identifier(_ activation: PluginActivation) throws -> String {
        guard let id = activation.payload["id"].string else {
            throw RPCError("params", "A conversation ID is required.")
        }
        return id
    }
}
