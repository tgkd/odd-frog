import AppKit

@MainActor
final class ResultRowView: NSTableCellView {
    enum Requirement {
        case required
        case optional
    }

    static let identifier = NSUserInterfaceItemIdentifier("ResultRow")
    static let iconSide: CGFloat = 24

    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")
    let requirementLabel = NSTextField(labelWithString: "")
    let kindLabel = NSTextField(labelWithString: "")
    private let detailStack: NSStackView
    private var appliedFont: ContentFont?

    init() {
        iconView.imageScaling = .scaleProportionallyDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(textStyle: .title2)

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for label in [subtitleLabel, valueLabel] {
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            label.usesSingleLineMode = true
            label.cell?.truncatesLastVisibleLine = true
        }
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        valueLabel.textColor = .labelColor
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        requirementLabel.textColor = .tertiaryLabelColor

        kindLabel.textColor = .tertiaryLabelColor
        kindLabel.alignment = .right
        kindLabel.setContentHuggingPriority(.required, for: .horizontal)
        kindLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let detailStack = NSStackView(views: [subtitleLabel, valueLabel, requirementLabel])
        detailStack.orientation = .horizontal
        self.detailStack = detailStack

        let textStack = NSStackView(views: [titleLabel, detailStack])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0

        let rowStack = NSStackView(views: [iconView, textStack, kindLabel])
        rowStack.orientation = .horizontal
        rowStack.distribution = .fill

        super.init(frame: .zero)
        identifier = Self.identifier

        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSide),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSide),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: rowStack.spacing),
            bottomAnchor.constraint(equalTo: rowStack.bottomAnchor, constant: rowStack.spacing),
        ])

        textField = titleLabel
        imageView = iconView
        applyFonts()
    }

    required init?(coder: NSCoder) { nil }

    private func applyFonts() {
        guard appliedFont != ContentFont.current else { return }
        appliedFont = ContentFont.current
        titleLabel.font = ContentFont.current.font(.body)
        for label in [subtitleLabel, valueLabel, requirementLabel, kindLabel] {
            label.font = ContentFont.current.font(.subheadline)
        }
    }

    func configure(title: String, detail: String?, value: String?, tooltip: String?, kind: String?, requirement: Requirement?, icon: NSImage?) {
        applyFonts()
        titleLabel.stringValue = title
        toolTip = tooltip
        iconView.image = icon
        subtitleLabel.stringValue = detail ?? ""
        detailStack.isHidden = detail == nil
        valueLabel.stringValue = value ?? ""
        valueLabel.isHidden = value == nil
        if let requirement {
            requirementLabel.stringValue = requirement == .required ? "Required" : "Optional"
            requirementLabel.isHidden = false
        } else {
            requirementLabel.isHidden = true
        }
        kindLabel.stringValue = kind ?? ""
    }
}
