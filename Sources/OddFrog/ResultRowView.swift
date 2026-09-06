import AppKit

@MainActor
final class ResultRowView: NSTableCellView {
    enum Chip {
        case required
        case optional
    }

    static let identifier = NSUserInterfaceItemIdentifier("ResultRow")
    static let singleLineHeight: CGFloat = 36
    static let twoLineHeight: CGFloat = 40

    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")
    let kindLabel = NSTextField(labelWithString: "")
    private let chipView = ChipView()
    private let textBlock = NSView()
    private var twoLine: [NSLayoutConstraint] = []
    private var oneLine: [NSLayoutConstraint] = []

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingTail
        for label in [subtitleLabel, valueLabel] {
            label.font = .systemFont(ofSize: 11)
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            label.usesSingleLineMode = true
            label.cell?.truncatesLastVisibleLine = true
        }
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        valueLabel.font = .systemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .labelColor
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        kindLabel.font = .systemFont(ofSize: 11)
        kindLabel.textColor = .tertiaryLabelColor
        kindLabel.alignment = .right
        kindLabel.setContentHuggingPriority(.required, for: .horizontal)
        kindLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        chipView.isHidden = true

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for v in [iconView, textBlock, kindLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for v in [titleLabel, subtitleLabel, valueLabel, chipView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            textBlock.addSubview(v)
        }
        let chipTrailing = chipView.trailingAnchor.constraint(lessThanOrEqualTo: textBlock.trailingAnchor)
        chipTrailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            textBlock.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textBlock.centerYAnchor.constraint(equalTo: centerYAnchor),
            textBlock.trailingAnchor.constraint(equalTo: kindLabel.leadingAnchor, constant: -8),
            kindLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            kindLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: textBlock.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: textBlock.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: textBlock.topAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: textBlock.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: textBlock.trailingAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor, constant: 3),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: textBlock.trailingAnchor),
            valueLabel.firstBaselineAnchor.constraint(equalTo: subtitleLabel.firstBaselineAnchor),
            chipView.leadingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor, constant: 6),
            chipView.centerYAnchor.constraint(equalTo: subtitleLabel.centerYAnchor),
            chipTrailing,
        ])
        twoLine = [
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.bottomAnchor.constraint(equalTo: textBlock.bottomAnchor),
        ]
        oneLine = [titleLabel.bottomAnchor.constraint(equalTo: textBlock.bottomAnchor)]
        NSLayoutConstraint.activate(oneLine)
    }

    required init?(coder: NSCoder) { nil }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyPalette() }
    }

    private func applyPalette() {
        guard backgroundStyle == .emphasized else {
            titleLabel.textColor = .labelColor
            subtitleLabel.textColor = .secondaryLabelColor
            valueLabel.textColor = .labelColor
            kindLabel.textColor = .tertiaryLabelColor
            chipView.tint = .tertiaryLabelColor
            return
        }
        let ink = SelectionPalette.ink(effectiveAppearance)
        titleLabel.textColor = ink.primary
        subtitleLabel.textColor = ink.secondary
        valueLabel.textColor = ink.primary
        kindLabel.textColor = ink.tertiary
        chipView.tint = ink.secondary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    func configure(title: String, detail: String?, value: String?, tooltip: String?, kind: String?, chip: Chip?, icon: NSImage?) {
        titleLabel.stringValue = title
        toolTip = tooltip
        valueLabel.stringValue = value ?? ""
        valueLabel.isHidden = value == nil
        if let chip {
            chipView.apply(chip)
            chipView.isHidden = false
        } else {
            chipView.isHidden = true
        }
        if let detail {
            subtitleLabel.stringValue = detail
            subtitleLabel.isHidden = false
            NSLayoutConstraint.deactivate(oneLine)
            NSLayoutConstraint.activate(twoLine)
        } else {
            subtitleLabel.stringValue = ""
            subtitleLabel.isHidden = true
            NSLayoutConstraint.deactivate(twoLine)
            NSLayoutConstraint.activate(oneLine)
        }
        kindLabel.stringValue = kind ?? ""
        iconView.image = icon
    }

    @MainActor
    private final class ChipView: NSView {
        private let label = NSTextField(labelWithString: "")
        private let border = CAShapeLayer()

        var tint: NSColor = .tertiaryLabelColor {
            didSet { applyTint() }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            border.fillColor = nil
            border.lineWidth = 0.5
            layer?.addSublayer(border)
            label.font = .systemFont(ofSize: 10)
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                heightAnchor.constraint(equalToConstant: 12),
            ])
            applyTint()
        }

        required init?(coder: NSCoder) { nil }

        func apply(_ chip: Chip) {
            switch chip {
            case .required:
                label.stringValue = "Required"
                label.font = .systemFont(ofSize: 10, weight: .medium)
                border.lineDashPattern = nil
            case .optional:
                label.stringValue = "Optional"
                label.font = .systemFont(ofSize: 10, weight: .regular)
                border.lineDashPattern = [2, 2]
            }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            border.frame = bounds
            border.path = CGPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), cornerWidth: 4, cornerHeight: 4, transform: nil)
            CATransaction.commit()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            applyTint()
        }

        private func applyTint() {
            label.textColor = tint
            effectiveAppearance.performAsCurrentDrawingAppearance {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                border.strokeColor = tint.cgColor
                CATransaction.commit()
            }
        }
    }
}
