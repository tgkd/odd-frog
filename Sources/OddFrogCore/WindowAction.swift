import CoreGraphics
import Foundation

public enum WindowEdge: String, Sendable, Hashable, CaseIterable {
    case left, right, top, bottom
}

public struct WindowFraction: Sendable, Hashable {
    public let numerator: Int
    public let denominator: Int

    public init(numerator: Int, denominator: Int) {
        precondition(numerator > 0 && denominator >= numerator)
        self.numerator = numerator
        self.denominator = denominator
    }

    public var value: Double { Double(numerator) / Double(denominator) }

    public var label: String {
        switch (numerator, denominator) {
        case (1, 2): "½"
        case (2, 3): "⅔"
        case (3, 4): "¾"
        default: "\(numerator)/\(denominator)"
        }
    }

    public var slug: String { "\(numerator)-\(denominator)" }
}

public enum WindowAction: Sendable, Hashable {
    case place(WindowEdge, WindowFraction)
    case maximize
    case tidy

    public static func serviceAction(_ id: String) -> WindowAction? {
        if id == "maximize" { return .maximize }
        if id == "tidy" { return .tidy }
        let fields = id.split(separator: ":")
        guard fields.count == 3, fields[0] == "place", let edge = WindowEdge(rawValue: String(fields[1])) else { return nil }
        let parts = fields[2].split(separator: "-")
        guard parts.count == 2, let numerator = Int(parts[0]), let denominator = Int(parts[1]),
              numerator > 0, denominator >= numerator, denominator <= 100 else { return nil }
        return .place(edge, WindowFraction(numerator: numerator, denominator: denominator))
    }
    public var id: String {
        switch self {
        case .place(let edge, let fraction): "window:place:\(edge.rawValue):\(fraction.slug)"
        case .maximize: "window:maximize"
        case .tidy: "window:tidy"
        }
    }

}

public enum WindowLayout {
    public static func frame(for action: WindowAction, in visible: CGRect) -> CGRect? {
        switch action {
        case .maximize:
            return visible
        case .tidy:
            return nil
        case .place(let edge, let fraction):
            let width = (visible.width * fraction.value).rounded()
            let height = (visible.height * fraction.value).rounded()
            switch edge {
            case .left:
                return CGRect(x: visible.minX, y: visible.minY, width: width, height: visible.height)
            case .right:
                return CGRect(x: visible.maxX - width, y: visible.minY, width: width, height: visible.height)
            case .top:
                return CGRect(x: visible.minX, y: visible.maxY - height, width: visible.width, height: height)
            case .bottom:
                return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: height)
            }
        }
    }

    public static func cascade(count: Int, in visible: CGRect, step: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [visible] }
        let gaps = CGFloat(count - 1)
        let effectiveStep = min(max(0, step), visible.width / 2 / gaps, visible.height / 2 / gaps)
        let width = (visible.width - gaps * effectiveStep).rounded()
        let height = (visible.height - gaps * effectiveStep).rounded()
        return (0..<count).map { index in
            let offset = CGFloat(index) * effectiveStep
            return CGRect(x: visible.minX + offset, y: visible.maxY - offset - height, width: width, height: height)
        }
    }

    public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
