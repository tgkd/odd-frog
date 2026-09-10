import Foundation

public enum PluginProtocol {
    public static let version = 2
    public static let maxBytes = 4 * 1024 * 1024
    public static func encoder() -> JSONEncoder {
        let value = JSONEncoder(); value.dateEncodingStrategy = .secondsSince1970; return value
    }
    public static func decoder() -> JSONDecoder {
        let value = JSONDecoder(); value.dateDecodingStrategy = .secondsSince1970; return value
    }
}

public enum JSONValue: Codable, Sendable, Hashable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .number(Double(v)) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    public subscript(_ key: String) -> JSONValue { if case .object(let v) = self { v[key] ?? .null } else { .null } }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var number: Double? { if case .number(let v) = self { v } else { nil } }
    public var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    public static func encode<T: Encodable>(_ value: T) throws -> Self {
        try PluginProtocol.decoder().decode(Self.self, from: PluginProtocol.encoder().encode(value))
    }
    public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try PluginProtocol.decoder().decode(type, from: PluginProtocol.encoder().encode(self))
    }
}

public struct RPCError: Error, Codable, Sendable, Equatable, CustomStringConvertible {
    public var code: String
    public var message: String
    public var description: String { message }
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
}

/// Exactly one of method, result, error. Requests have IDs; events do not.
public struct PluginEnvelope: Codable, Sendable {
    public var apiVersion = PluginProtocol.version
    public var id: String?
    public var method: String?
    public var params: JSONValue?
    public var result: JSONValue?
    public var error: RPCError?
    public init(id: String? = nil, method: String? = nil, params: JSONValue? = nil,
                result: JSONValue? = nil, error: RPCError? = nil) {
        self.id = id; self.method = method; self.params = params; self.result = result; self.error = error
    }
    enum CodingKeys: String, CodingKey { case apiVersion, id, method, params, result, error }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try c.decode(Int.self, forKey: .apiVersion)
        id = try c.decodeIfPresent(String.self, forKey: .id); method = try c.decodeIfPresent(String.self, forKey: .method)
        params = try c.decodeIfPresent(JSONValue.self, forKey: .params)
        result = c.contains(.result) ? try c.decode(JSONValue.self, forKey: .result) : nil
        error = try c.decodeIfPresent(RPCError.self, forKey: .error)
    }
    public func validate() throws {
        guard apiVersion == PluginProtocol.version, [method != nil, result != nil, error != nil].filter({ $0 }).count == 1,
              id == nil || id?.isEmpty == false, method == nil || method?.isEmpty == false,
              method != nil || (id != nil && params == nil) else {
            throw RPCError("protocol", "Invalid API 2 envelope.")
        }
    }
}

public struct PluginContext: Codable, Sendable {
    public var settings: [String: JSONValue]
    public var storagePath: String
    public var configPath: String
    public init(settings: [String: JSONValue] = [:], storagePath: String = "", configPath: String = "") {
        self.settings = settings; self.storagePath = storagePath; self.configPath = configPath
    }
}
public struct PluginQuery: Codable, Sendable {
    public var query: String
    public var fullQuery: String
    public var now: Date
    public var timeZoneIdentifier: String
    public var maxResults: Int
    public init(query: String, fullQuery: String, now: Date = Date(),
                timeZoneIdentifier: String = TimeZone.current.identifier, maxResults: Int = 8) {
        self.query = query; self.fullQuery = fullQuery; self.now = now
        self.timeZoneIdentifier = timeZoneIdentifier; self.maxResults = maxResults
    }
}
public struct PluginActivation: Codable, Sendable {
    public var actionID: String
    public var payload: JSONValue
    public var item: PluginItem
    public var argument: String?
    public var text: String?
    public init(actionID: String, payload: JSONValue, item: PluginItem, argument: String?, text: String? = nil) {
        self.actionID = actionID; self.payload = payload; self.item = item; self.argument = argument; self.text = text
    }
}
public struct PluginEffects: Codable, Sendable {
    public var notification: String?
    public var refreshCatalog: Bool
    public var refreshQuery: Bool
    public var view: PluginView?
    public init(notification: String? = nil, refreshCatalog: Bool = false, refreshQuery: Bool = false,
                view: PluginView? = nil) {
        self.notification = notification; self.refreshCatalog = refreshCatalog; self.refreshQuery = refreshQuery
        self.view = view
    }
}
