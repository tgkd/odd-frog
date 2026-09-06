import AppKit

enum SelectionPalette {
    static var fill: NSColor { .controlAccentColor }

    static func onFill(_ appearance: NSAppearance?) -> NSColor {
        var ink = NSColor.white
        (appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            ink = contrast(1.0, luminance(of: fill)) < minimumContrast ? .black : .white
        }
        return ink
    }

    private static let minimumContrast = 3.0

    private static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func luminance(of color: NSColor) -> Double {
        guard let srgb = color.usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(srgb.redComponent)
            + 0.7152 * channel(srgb.greenComponent)
            + 0.0722 * channel(srgb.blueComponent)
    }
}
