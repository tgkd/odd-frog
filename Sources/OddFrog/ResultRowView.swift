import AppKit

@MainActor
final class ResultRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultRow")
    static let singleLineHeight: CGFloat = 36
    static let twoLineHeight: CGFloat = 40

    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")
    let kindLabel = NSTextField(labelWithString: "")
    private let textBlock = NSView()
    private var twoLine: [NSLayoutConstraint] = []
    private var oneLine: [NSLayoutConstraint] = []

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
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
        valueLabel.textColor = .labelColor
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        kindLabel.font = .systemFont(ofSize: 11)
        kindLabel.textColor = .tertiaryLabelColor
        kindLabel.alignment = .right
        kindLabel.setContentHuggingPriority(.required, for: .horizontal)
        kindLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for v in [iconView, textBlock, kindLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for v in [titleLabel, subtitleLabel, valueLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            textBlock.addSubview(v)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            textBlock.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textBlock.centerYAnchor.constraint(equalTo: centerYAnchor),
            textBlock.trailingAnchor.constraint(equalTo: kindLabel.leadingAnchor, constant: -8),
            kindLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            kindLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: textBlock.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: textBlock.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: textBlock.topAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: textBlock.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: textBlock.trailingAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor, constant: 3),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: textBlock.trailingAnchor),
            valueLabel.firstBaselineAnchor.constraint(equalTo: subtitleLabel.firstBaselineAnchor),
        ])
        twoLine = [
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.bottomAnchor.constraint(equalTo: textBlock.bottomAnchor),
        ]
        oneLine = [titleLabel.bottomAnchor.constraint(equalTo: textBlock.bottomAnchor)]
        NSLayoutConstraint.activate(oneLine)
    }

    required init?(coder: NSCoder) { nil }

    func configure(title: String, detail: String?, value: String?, tooltip: String?, kind: String?, icon: NSImage?) {
        titleLabel.stringValue = title
        toolTip = tooltip
        valueLabel.stringValue = value ?? ""
        valueLabel.isHidden = value == nil
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
}
