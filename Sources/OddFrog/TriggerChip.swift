import AppKit

/// The plugin name shown left of the query while the launcher is inside that plugin.
@MainActor
final class TriggerChip: NSView {
    private let label = NSTextField(labelWithString: "")

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: 3),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        applyContentFont()
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
    }

    func applyContentFont() {
        label.font = ContentFont.current.font(.title3)
    }
}
