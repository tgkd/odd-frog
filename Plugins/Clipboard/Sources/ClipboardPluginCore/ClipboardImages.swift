import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ClipboardImages {
    public nonisolated static func process(_ data: Data, type: ClipboardCapture.ImageType,
                                           maxOutputBytes: Int = ClipboardLimits.maxImageBytes) -> ProcessedImage? {
        guard data.count <= ClipboardLimits.maxImageSourceBytes else {
            return nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= ClipboardLimits.maxImagePixels / height else {
            return nil
        }
        let full: Data
        if type == .png {
            full = data
        } else {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let reencoded = encode(image, type: .png) else {
                return nil
            }
            full = reencoded
        }
        guard full.count <= maxOutputBytes else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: ClipboardLimits.thumbnailPixels,
        ]
        guard let thumbnailImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let thumbnail = encode(thumbnailImage, type: .png) else {
            return nil
        }
        return ProcessedImage(png: full, thumbnail: thumbnail, width: width, height: height)
    }

    private static func encode(_ image: CGImage, type: UTType) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }
}
