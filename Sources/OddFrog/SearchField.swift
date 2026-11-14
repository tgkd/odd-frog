import AppKit

@MainActor
final class SearchField: NSTextField {
    static let placeholder = "Search…"

    init() {
        super.init(frame: .zero)
        isBezeled = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = ContentFont.current.font(.title2)
        placeholderString = Self.placeholder
        lineBreakMode = .byTruncatingTail
        usesSingleLineMode = false
        cell?.wraps = false
        cell?.isScrollable = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }
}
