import AppKit

struct SelectionInk {
    let primary: NSColor
    let secondary: NSColor
    let tertiary: NSColor
}

enum SelectionPalette {
    static var fill: NSColor { .selectedContentBackgroundColor }

    static func ink(_ appearance: NSAppearance?) -> SelectionInk {
        var result = SelectionInk(primary: .white, secondary: .white, tertiary: .white)
        (appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            let background = components(of: fill)
            let backgroundLuminance = luminance(background)
            let preferred = components(of: .alternateSelectedControlTextColor)
            let base = contrast(luminance(preferred), backgroundLuminance) >= textTarget
                ? preferred
                : bestInk(on: backgroundLuminance)
            result = SelectionInk(
                primary: colour(base, over: background, weight: 1),
                secondary: colour(base, over: background, weight: 0.85),
                tertiary: colour(base, over: background, weight: 0.7)
            )
        }
        return result
    }

    private static let textTarget = 4.5

    private static func bestInk(on backgroundLuminance: Double) -> [Double] {
        contrast(1, backgroundLuminance) >= contrast(0, backgroundLuminance) ? [1, 1, 1] : [0, 0, 0]
    }

    private static func colour(_ ink: [Double], over background: [Double], weight: Double) -> NSColor {
        var applied = weight
        while applied < 1 {
            let blended = blend(ink, over: background, weight: applied)
            if contrast(luminance(blended), luminance(background)) >= textTarget { break }
            applied += 0.05
        }
        let final = blend(ink, over: background, weight: min(applied, 1))
        return NSColor(srgbRed: final[0], green: final[1], blue: final[2], alpha: 1)
    }

    private static func blend(_ ink: [Double], over background: [Double], weight: Double) -> [Double] {
        zip(ink, background).map { weight * $0 + (1 - weight) * $1 }
    }

    private static func components(of color: NSColor) -> [Double] {
        guard let srgb = color.usingColorSpace(.sRGB) else { return [0, 0, 0] }
        return [Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent)]
    }

    private static func luminance(_ rgb: [Double]) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2])
    }

    private static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

private extension NSColor {
    convenience init(srgbRed: Double, green: Double, blue: Double, alpha: Double) {
        self.init(srgbRed: CGFloat(srgbRed), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
