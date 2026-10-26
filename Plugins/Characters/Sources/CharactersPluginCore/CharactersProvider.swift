import Foundation
import OddFrogPluginAPI

public enum CharactersProvider {
    public static func respond(to request: PluginQuery, kind: CharacterKind, catalog: CharacterCatalog) -> [PluginItem] {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = max(1, min(request.maxResults, 50))
        let matches = query.isEmpty ? catalog.featured : catalog.search(query)
        if matches.isEmpty {
            return [PluginItem(id: "empty", title: kind == .emoji ? "No emoji found" : "No symbols found",
                               subtitle: "Try another word, for example “heart” or “arrow”.",
                               kind: label(kind), symbol: "magnifyingglass")]
        }
        return matches.prefix(cap).map { row($0, kind: kind) }
    }

    private static func label(_ kind: CharacterKind) -> String {
        kind == .emoji ? "Emoji" : "Symbol"
    }

    private static func row(_ entry: CharacterEntry, kind: CharacterKind) -> PluginItem {
        PluginItem(id: entry.code, title: entry.name, subtitle: entry.code,
                   kind: label(kind), icon: PluginItem.glyphIcon(entry.glyph),
                   primary: PluginAction(.paste, entry.glyph),
                   secondary: PluginAction(.copy, entry.glyph))
    }
}
