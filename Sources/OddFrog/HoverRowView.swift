import AppKit

@MainActor
final class HoverRowView: NSTableRowView {
    static let cornerRadius: CGFloat = 6
    static let sideInset: CGFloat = 2

    var onHoverChange: ((Bool) -> Void)?

    private var hoverArea: NSTrackingArea?

    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
            onHoverChange?(isHovered)
        }
    }

    override var isEmphasized: Bool {
        get { true }
        set { _ = newValue }
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        SelectionPalette.fill.setFill()
        rowPath.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered, !isSelected else { return }
        NSColor.quaternaryLabelColor.setFill()
        rowPath.fill()
    }

    private var rowPath: NSBezierPath {
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: Self.sideInset, dy: 0),
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        )
    }
}
