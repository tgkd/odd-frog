import Foundation
import OddFrogPluginAPI

public struct ClipboardLimits: Sendable, Equatable {
    public static let maxTextBytes = 65_536
    public static let maxImageSourceBytes = 10_485_760
    public static let maxImagePixels = 40_000_000
    public static let maxImageBytes = 20_971_520
    public static let thumbnailPixels = 64

    public var count: Int
    public var captureImages: Bool
    public var maxTotalImageBytes: Int
    public init(count: Int, captureImages: Bool, maxTotalImageBytes: Int = 209_715_200) {
        self.count = count
        self.captureImages = captureImages
        self.maxTotalImageBytes = maxTotalImageBytes
    }
    public init(settings: [String: JSONValue]) {
        let limit = settings["limit"]?.number.map { Int($0.rounded()) } ?? 50
        count = min(max(limit, 1), 200)
        captureImages = settings["capture_images"]?.bool ?? true
        maxTotalImageBytes = 209_715_200
    }
}
