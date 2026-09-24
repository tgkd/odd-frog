import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
import ClipboardPluginCore

struct ClipboardImagesTests {
    private func makeImageData(width: Int, height: Int, type: UTType) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private var pngMagic: Data { Data([0x89, 0x50, 0x4E, 0x47]) }

    @Test func pngPassesThroughWithDimensionsAndThumbnail() throws {
        let png = makeImageData(width: 20, height: 10, type: .png)
        let processed = try #require(ClipboardImages.process(png, type: .png))
        #expect(processed.png == png)
        #expect(processed.width == 20)
        #expect(processed.height == 10)
        #expect(processed.thumbnail.prefix(4) == pngMagic)
    }

    @Test func tiffIsReencodedToPNG() throws {
        let tiff = makeImageData(width: 8, height: 8, type: .tiff)
        let processed = try #require(ClipboardImages.process(tiff, type: .tiff))
        #expect(processed.png != tiff)
        #expect(processed.png.prefix(4) == pngMagic)
        #expect(processed.width == 8)
        #expect(processed.height == 8)
    }

    @Test func oversizedSourcesAreRejected() {
        let big = Data(repeating: 0, count: ClipboardLimits.maxImageSourceBytes + 1)
        #expect(ClipboardImages.process(big, type: .png) == nil)
    }

    @Test func nonImageDataIsRejected() {
        let text = Data("not an image".utf8)
        #expect(ClipboardImages.process(text, type: .png) == nil)
        #expect(ClipboardImages.process(text, type: .tiff) == nil)
    }
}
