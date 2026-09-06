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

    public var id: String {
        switch self {
        case .place(let edge, let fraction): "window:place:\(edge.rawValue):\(fraction.slug)"
        case .maximize: "window:maximize"
        case .tidy: "window:tidy"
        }
    }

    public var title: String {
        switch self {
        case .place(let edge, let fraction): "\(edge.rawValue.capitalized) \(fraction.label)"
        case .maximize: "Maximize"
        case .tidy: "Tidy Windows"
        }
    }

    public var subtitle: String? {
        switch self {
        case .place, .maximize: nil
        case .tidy: "Cascade every window on this screen"
        }
    }

    public var kindLabel: String { "Window" }

    public static let all: [WindowAction] = [
        .place(.left, WindowFraction(numerator: 1, denominator: 2)),
        .place(.right, WindowFraction(numerator: 1, denominator: 2)),
        .place(.left, WindowFraction(numerator: 2, denominator: 3)),
        .place(.right, WindowFraction(numerator: 2, denominator: 3)),
        .place(.top, WindowFraction(numerator: 1, denominator: 2)),
        .place(.bottom, WindowFraction(numerator: 1, denominator: 2)),
        .place(.top, WindowFraction(numerator: 3, denominator: 4)),
        .place(.bottom, WindowFraction(numerator: 3, denominator: 4)),
        .maximize,
        .tidy,
    ]
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
