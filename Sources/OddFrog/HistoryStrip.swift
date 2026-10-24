import AppKit
import OddFrogCore

/// Recent queries under the results while ↑/↓ walk the history, newest at the bottom so ↑ moves up the list.
@MainActor
final class HistoryStrip: NSView {
    static let visibleCount = 5

    private let caption = NSTextField(labelWithString: "History")
    private let stack = NSStackView()
    private var rows: [HistoryRow] = []
    var onPick: ((Int) -> Void)?

    init() {
        super.init(frame: .zero)
        caption.textColor = .tertiaryLabelColor
        // The stack aligns its views to its width at default-low priority; labels must hug less than that.
        caption.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        caption.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(caption)
        addSubview(stack)
        // Matches the inset table style of the results above: 10pt to the row edge, 10pt more to the text.
        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2 * HistoryRow.inset),
            trailingAnchor.constraint(equalTo: caption.trailingAnchor, constant: 2 * HistoryRow.inset),
            caption.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HistoryRow.inset),
            trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: HistoryRow.inset),
            bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
        ])
        applyContentFont()
    }

    required init?(coder: NSCoder) { nil }

    func show(history: [String], current: Int) {
        let window = QueryHistory.window(around: current, count: Self.visibleCount, total: history.count)
        let indices = Array(window.reversed())
        while rows.count < indices.count {
            let row = HistoryRow()
            row.onClick = { [weak self, weak row] in
                guard let self, let row, let index = row.index else { return }
                onPick?(index)
            }
            rows.append(row)
            stack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            ])
        }
        for (slot, row) in rows.enumerated() {
            guard slot < indices.count else { row.isHidden = true; continue }
            let index = indices[slot]
            row.isHidden = false
            row.index = index
            row.configure(text: history[index], current: index == current)
        }
    }

    func applyContentFont() {
        caption.font = ContentFont.current.font(.subheadline)
        for row in rows { row.applyContentFont() }
    }
}

@MainActor
private final class HistoryRow: NSView {
    static let inset: CGFloat = 10

    private let label = NSTextField(labelWithString: "")
    private var current = false
    var index: Int?
    var onClick: (() -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: Self.inset),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: 3),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
        applyContentFont()
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = current ? NSColor.unemphasizedSelectedContentBackgroundColor.cgColor : nil
    }

    func configure(text: String, current: Bool) {
        label.stringValue = text
        label.textColor = current ? .labelColor : .secondaryLabelColor
        self.current = current
        needsDisplay = true
    }

    func applyContentFont() {
        label.font = ContentFont.current.font(.body)
    }

    @objc private func clicked() { onClick?() }
}
