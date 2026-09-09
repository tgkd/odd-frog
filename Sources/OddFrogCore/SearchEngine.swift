import Foundation

public struct RankedItem: Sendable, Equatable {
    public let item: LauncherItem
    public let lexical: Double
    public let weight: Double
    public let exactAlias: Bool
    public let argument: String?

    public init(item: LauncherItem, lexical: Double, weight: Double, exactAlias: Bool, argument: String? = nil) {
        self.item = item
        self.lexical = lexical
        self.weight = weight
        self.exactAlias = exactAlias
        self.argument = argument
    }

    public var bonus: Double { SearchEngine.frecencyBonus(weight) }
    public var score: Double { lexical + bonus }
}

public enum SearchEngine {
    public static let frecencyCap = 15.0
    public static let frecencyK = 3.0

    public static func frecencyBonus(_ weight: Double) -> Double {
        guard weight > 0 else { return 0 }
        return frecencyCap * weight / (weight + frecencyK)
    }

    public static func search(
        query: String,
        items: [LauncherItem],
        weights: [String: Double],
        maxResults: Int
    ) -> [RankedItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return recent(items: items, weights: weights, maxResults: maxResults)
        }
        var ranked: [RankedItem] = []
        ranked.reserveCapacity(items.count)
        for item in items {
            let weight = weights[item.id] ?? 0
            var queries = splits(of: trimmed, allowArgument: item.acceptsArgument)
            if let kind = item.kindLabel {
                if trimmed.caseInsensitiveCompare(kind) == .orderedSame {
                    let exact = item.aliases.contains(trimmed.lowercased())
                    ranked.append(RankedItem(item: item, lexical: 100, weight: weight, exactAlias: exact))
                    continue
                }
                let prefix = kind + " "
                if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                    let itemQuery = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    queries += splits(of: itemQuery, allowArgument: item.acceptsArgument)
                }
            }
            for (query, argument) in queries {
                guard let (lexical, exact) = match(query: query, item: item) else { continue }
                ranked.append(RankedItem(item: item, lexical: lexical, weight: weight, exactAlias: exact, argument: argument))
                break
            }
        }
        ranked.sort(by: order)
        return Array(ranked.prefix(maxResults))
    }

    static func match(query: String, item: LauncherItem) -> (lexical: Double, exact: Bool)? {
        let lowered = query.lowercased()
        if item.aliases.contains(lowered) { return (100, true) }
        var best = FuzzyScorer.normalized(query: query, candidate: item.title)
        for alias in item.aliases {
            if let s = FuzzyScorer.normalized(query: query, candidate: alias) {
                best = max(best ?? 0, s)
            }
        }
        guard let lexical = best else { return nil }
        return (lexical, false)
    }

    static func splits(of query: String, allowArgument: Bool) -> [(String, String?)] {
        var out: [(String, String?)] = [(query, nil)]
        guard allowArgument else { return out }
        var index = query.endIndex
        while let space = query[..<index].lastIndex(of: " ") {
            let head = query[..<space].trimmingCharacters(in: .whitespaces)
            let tail = query[query.index(after: space)...].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty, !tail.isEmpty { out.append((head, tail)) }
            index = space
        }
        return out
    }

    static func order(_ a: RankedItem, _ b: RankedItem) -> Bool {
        if a.exactAlias != b.exactAlias { return a.exactAlias }
        if a.score != b.score { return a.score > b.score }
        if a.weight != b.weight { return a.weight > b.weight }
        let byTitle = a.item.title.localizedCaseInsensitiveCompare(b.item.title)
        if byTitle != .orderedSame { return byTitle == .orderedAscending }
        return a.item.id < b.item.id
    }

    static func recent(items: [LauncherItem], weights: [String: Double], maxResults: Int) -> [RankedItem] {
        let used = items
            .compactMap { item -> RankedItem? in
                guard let w = weights[item.id], w > 0 else { return nil }
                return RankedItem(item: item, lexical: 0, weight: w, exactAlias: false)
            }
            .sorted(by: order)
        return Array(used.prefix(maxResults))
    }
}
