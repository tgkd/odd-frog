import Foundation

/// Thin dlopen wrapper over the fff C library (https://github.com/dmtrKovalenko/fff.nvim).
/// The library is loaded at runtime so builds and tests work without it.
public final class FffLibrary: @unchecked Sendable {
    public typealias Handle = UnsafeMutableRawPointer

    public struct Hit: Sendable, Equatable {
        public var relativePath: String
        public var isDirectory: Bool
        public var score: Int
        public init(relativePath: String, isDirectory: Bool, score: Int) {
            self.relativePath = relativePath; self.isDirectory = isDirectory; self.score = score
        }
    }

    public struct LoadError: Error, CustomStringConvertible {
        public var description: String
    }

    private typealias Create = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                                               Bool, Bool, Bool, Bool, Bool) -> UnsafeMutableRawPointer?
    private typealias Destroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias SearchMixed = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                                                    UInt32, UInt32, UInt32, Int32, UInt32) -> UnsafeMutableRawPointer?
    private typealias IsScanning = @convention(c) (UnsafeMutableRawPointer?) -> Bool
    private typealias TrackQuery = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
    private typealias FreeResult = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias Success = @convention(c) (UnsafeRawPointer?) -> Bool
    private typealias ErrorText = @convention(c) (UnsafeRawPointer?) -> UnsafePointer<CChar>?
    private typealias PayloadHandle = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    private typealias MixedItem = @convention(c) (UnsafeRawPointer?, UInt32) -> UnsafeRawPointer?
    private typealias IntValue = @convention(c) (UnsafeRawPointer?) -> Int64

    private let create: Create
    private let destroyInstance: Destroy
    private let searchMixed: SearchMixed
    private let isScanningFn: IsScanning
    private let trackQueryFn: TrackQuery
    private let freeResult: FreeResult
    private let freeMixed: FreeResult
    private let success: Success
    private let errorText: ErrorText
    private let payloadHandle: PayloadHandle
    private let mixedItem: MixedItem
    private let mixedScore: MixedItem
    private let intValue: IntValue

    /// Byte offsets inside the repr(C) `FffMixedItem` (`item_type`, `relative_path`). Stable fff has no
    /// accessors for them; the offsets come from the pinned header. `FffScore.total` is its first field.
    private static let typeOffset = 0
    private static let pathOffset = 8

    public static func candidatePaths(bundle: Bundle = .main) -> [String] {
        var paths: [String] = []
        if let override = ProcessInfo.processInfo.environment["ODDFROG_FFF_LIBRARY"] { paths.append(override) }
        if let frameworks = bundle.privateFrameworksPath { paths.append(frameworks + "/libfff_c.dylib") }
        paths += ["/opt/homebrew/lib/libfff_c.dylib", "/usr/local/lib/libfff_c.dylib"]
        return paths
    }

    public static func load(candidates: [String] = candidatePaths()) throws -> FffLibrary {
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if let image = dlopen(path, RTLD_NOW | RTLD_LOCAL) { return try FffLibrary(image: image) }
        }
        throw LoadError(description: "libfff_c.dylib was not found. Run scripts/fetch-fff.sh and rebuild the app.")
    }

    private init(image: UnsafeMutableRawPointer) throws {
        func symbol<T>(_ name: String, as _: T.Type) throws -> T {
            guard let pointer = dlsym(image, name) else { throw LoadError(description: "fff library lacks \(name).") }
            return unsafeBitCast(pointer, to: T.self)
        }
        create = try symbol("fff_create_instance", as: Create.self)
        destroyInstance = try symbol("fff_destroy", as: Destroy.self)
        searchMixed = try symbol("fff_search_mixed", as: SearchMixed.self)
        isScanningFn = try symbol("fff_is_scanning", as: IsScanning.self)
        trackQueryFn = try symbol("fff_track_query", as: TrackQuery.self)
        freeResult = try symbol("fff_free_result", as: FreeResult.self)
        freeMixed = try symbol("fff_free_mixed_search_result", as: FreeResult.self)
        success = try symbol("fff_result_get_success", as: Success.self)
        errorText = try symbol("fff_result_get_error", as: ErrorText.self)
        payloadHandle = try symbol("fff_result_get_handle", as: PayloadHandle.self)
        mixedItem = try symbol("fff_mixed_search_result_get_item", as: MixedItem.self)
        mixedScore = try symbol("fff_mixed_search_result_get_score", as: MixedItem.self)
        intValue = try symbol("fff_result_get_int_value", as: IntValue.self)
    }

    /// Starts indexing `root` in the background. `database` is a directory for the frecency and query history.
    public func open(root: String, database: String) throws -> Handle {
        try FileManager.default.createDirectory(atPath: database, withIntermediateDirectories: true)
        let result = create(root, database + "/frecency", database + "/history", false, true, false, true, false)
        defer { freeResult(result) }
        guard success(result) else { throw LoadError(description: message(result)) }
        guard let handle = payloadHandle(result) else { throw LoadError(description: "fff returned no index handle.") }
        return handle
    }

    public func close(_ handle: Handle) { destroyInstance(handle) }

    public func isScanning(_ handle: Handle) -> Bool { isScanningFn(handle) }

    /// Records that the file at the absolute `path` was opened for `query`, which raises its frecency.
    public func track(_ handle: Handle, query: String, path: String) throws {
        let result = trackQueryFn(handle, query, path)
        defer { freeResult(result) }
        guard success(result), intValue(result) == 1 else { throw LoadError(description: message(result)) }
    }

    public func search(_ handle: Handle, query: String, limit: Int) throws -> [Hit] {
        let result = searchMixed(handle, query, nil, 0, 0, UInt32(clamping: limit), 0, 0)
        defer { freeResult(result) }
        guard success(result) else { throw LoadError(description: message(result)) }
        guard let payload = payloadHandle(result) else { return [] }
        defer { freeMixed(payload) }
        var hits: [Hit] = []
        for index in 0..<UInt32(clamping: limit) {
            guard let item = mixedItem(payload, index) else { break }
            guard let path = item.load(fromByteOffset: Self.pathOffset, as: UnsafePointer<CChar>?.self) else { continue }
            let isDirectory = item.load(fromByteOffset: Self.typeOffset, as: UInt8.self) == 1
            let score = mixedScore(payload, index).map { Int($0.load(as: Int32.self)) } ?? 0
            hits.append(Hit(relativePath: String(cString: path), isDirectory: isDirectory, score: score))
        }
        return hits
    }

    private func message(_ result: UnsafeMutableRawPointer?) -> String {
        errorText(result).map { String(cString: $0) } ?? "Unknown fff error."
    }
}
