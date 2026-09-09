import Foundation
import CryptoKit
import OddFrogPluginAPI

public enum LinkService {
    private static func revision(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func read(from url: URL) throws -> JSONValue {
        let loaded = try ConfigLoader.load(from: url)
        let links: [JSONValue] = loaded.config.commands.compactMap { item in
            guard case .url(let url) = item.action else { return nil }
            return .object(["id": .string(item.stableID), "name": .string(item.name), "url": .string(URLTemplate.display(url)), "aliases": .array(item.aliases.map(JSONValue.string))])
        }
        return .object(["revision": .string(revision(loaded.contents)), "links": .array(links)])
    }
    public static func write(_ params: JSONValue, to url: URL) throws -> JSONValue {
        let loaded = try ConfigLoader.load(from: url)
        guard params["revision"].string == revision(loaded.contents) else { throw RPCError("revision", "Links changed. Read them again before saving.") }
        let original: CommandItem?
        if let id = params["id"].string {
            guard let item = loaded.config.commands.first(where: { $0.stableID == id }), case .url = item.action else { throw RPCError("params", "Link ID not found.") }
            original = item
        } else { original = nil }
        let draft: LinkDraft?
        if params["delete"].bool == true {
            guard original != nil else { throw RPCError("params", "Deletion requires a link ID.") }; draft = nil
        } else {
            guard let name = params["name"].string, let address = params["url"].string else { throw RPCError("params", "A name and URL are required.") }
            draft = LinkDraft(name: name, url: address, aliases: (params["aliases"].array ?? []).compactMap(\.string).joined(separator: ","))
        }
        let updated = try LinkEditor.updating(String(decoding: loaded.contents, as: UTF8.self), original: original, draft: draft)
        guard try Data(contentsOf: url) == loaded.contents else { throw RPCError("revision", "Config changed while saving. Retry.") }
        try Data(updated.utf8).write(to: url, options: .atomic)
        return try read(from: url)
    }
}
