import Foundation
import OddFrogPluginAPI

public actor CharactersHandler: ProviderHandler {
    private let kind: CharacterKind
    private var catalog: CharacterCatalog?

    public init(_ kind: CharacterKind) {
        self.kind = kind
    }

    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        switch method {
        case "initialize":
            return .object(["apiVersion": .number(2)])
        case "settings":
            return .object([:])
        case "query":
            let input = try params["input"].decode(PluginQuery.self)
            return try .encode(CharactersProvider.respond(to: input, kind: kind, catalog: loadedCatalog()))
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }

    // Building the emoji list reads Unicode names for thousands of scalars, so it waits for the first query.
    private func loadedCatalog() -> CharacterCatalog {
        if let catalog {
            return catalog
        }
        let built = kind == .emoji ? CharacterCatalog.emoji() : CharacterCatalog.symbols()
        catalog = built
        return built
    }
}
