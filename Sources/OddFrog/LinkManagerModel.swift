import Foundation
import Observation
import OddFrogCore

@Observable
@MainActor
final class LinkManagerModel {
    private(set) var links: [CommandItem] = []
    private(set) var selection: CommandItem.ID?
    private(set) var original: CommandItem?
    var name = ""
    var url = ""
    var aliases = ""
    private(set) var error: String?

    @ObservationIgnored var onApply: ((CommandItem?, LinkDraft?) throws -> [CommandItem])?
    @ObservationIgnored var onDone: (() -> Void)?

    func reset(links: [CommandItem]) {
        self.links = links
        newLink()
    }

    func newLink() {
        selection = nil
        original = nil
        name = ""
        url = ""
        aliases = ""
        error = nil
    }

    func select(_ id: CommandItem.ID?) {
        selection = id
        guard let id, let link = links.first(where: { $0.id == id }) else { return }
        original = link
        name = link.name
        url = Self.address(of: link)
        aliases = link.aliases.joined(separator: ", ")
        error = nil
    }

    func save() {
        let draft = LinkDraft(name: name, url: url, aliases: aliases)
        do {
            guard let onApply else { return }
            var saved = try draft.command()
            if let original { saved.stableID = original.stableID }
            links = try onApply(original, draft)
            if links.contains(where: { $0.id == saved.id }) {
                select(saved.id)
            }
            error = nil
        } catch {
            self.error = Self.describe(error)
        }
    }

    func delete() {
        guard let original else { return }
        do {
            guard let onApply else { return }
            links = try onApply(original, nil)
            newLink()
        } catch {
            self.error = Self.describe(error)
        }
    }

    static func address(of link: CommandItem) -> String {
        if case .url(let url) = link.action { return URLTemplate.display(url) }
        return ""
    }

    private static func describe(_ error: any Error) -> String {
        (error as? ConfigError)?.description ?? error.localizedDescription
    }
}
