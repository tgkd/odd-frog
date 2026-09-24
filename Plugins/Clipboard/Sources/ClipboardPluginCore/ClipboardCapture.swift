import Foundation

public enum ClipboardCapture: Sendable, Equatable {
    public enum ImageType: String, Sendable {
        case png
        case tiff
    }
    case text(String)
    case image(data: Data, type: ImageType)
}

public struct ProcessedImage: Sendable {
    public var png: Data
    public var thumbnail: Data
    public var width: Int
    public var height: Int
    public init(png: Data, thumbnail: Data, width: Int, height: Int) {
        self.png = png
        self.thumbnail = thumbnail
        self.width = width
        self.height = height
    }
}
