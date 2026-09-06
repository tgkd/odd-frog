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
            let base = components(of: .alternateSelectedControlTextColor)
            result = SelectionInk(
                primary: colour(base, over: background, weight: 1),
                secondary: colour(base, over: background, weight: 0.92),
                tertiary: colour(base, over: background, weight: 0.82)
            )
        }
        return result
    }

    private static func colour(_ ink: [Double], over background: [Double], weight: Double) -> NSColor {
        let blended = zip(ink, background).map { weight * $0 + (1 - weight) * $1 }
        return NSColor(
            srgbRed: CGFloat(blended[0]),
            green: CGFloat(blended[1]),
            blue: CGFloat(blended[2]),
            alpha: 1
        )
    }

    private static func components(of color: NSColor) -> [Double] {
        guard let srgb = color.usingColorSpace(.sRGB) else { return [0, 0, 0] }
        return [Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent)]
    }
}
