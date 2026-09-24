import Foundation

public struct ClipboardEntry: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case text
        case image
    }
    public var id: String
    public var kind: Kind
    public var text: String?
    public var width: Int?
    public var height: Int?
    public var byteSize: Int
    public var hash: String
    public var copied: Date
    public init(id: String, kind: Kind, text: String? = nil, width: Int? = nil, height: Int? = nil,
                byteSize: Int, hash: String, copied: Date) {
        self.id = id
        self.kind = kind
        self.text = text
        self.width = width
        self.height = height
        self.byteSize = byteSize
        self.hash = hash
        self.copied = copied
    }
    public static func title(for entry: ClipboardEntry) -> String {
        switch entry.kind {
        case .image:
            return "Image \(entry.width ?? 0)×\(entry.height ?? 0)"
        case .text:
            guard let line = entry.text?
                .split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) else {
                return ""
            }
            return String(line.prefix(80))
        }
    }
}
