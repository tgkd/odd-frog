import AppKit

@MainActor
final class SearchField: NSTextField {
    init() {
        super.init(frame: .zero)
        isBezeled = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 18, weight: .regular)
        placeholderAttributedString = NSAttributedString(
            string: "Search…",
            attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.placeholderTextColor]
        )
        lineBreakMode = .byTruncatingTail
        usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
    }

    required init?(coder: NSCoder) { nil }
}
