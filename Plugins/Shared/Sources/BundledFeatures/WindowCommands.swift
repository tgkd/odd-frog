import Foundation
import OddFrogCore

extension WindowAction {
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
