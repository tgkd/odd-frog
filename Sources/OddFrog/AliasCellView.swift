import AppKit

@MainActor
final class AliasCellView: NSTableCellView, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("aliasCell")

    var onCommit: (([String]) -> Void)?

    var isEditingAliases: Bool { editing }

    private let pill = AliasPill()
    private let labels = NSStackView()
    private let builtinLabel = NSTextField(labelWithString: "")
    private let customLabel = NSTextField(labelWithString: "")
    private let editor = NSTextField()

    private var builtinAliases: [String] = []
    private var customAliases: [String] = []
    private var hovered = false
    private var rowSelected = false
    private var editing = false

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyStyle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        buildLayout()
        applyContent()
    }

    required init?(coder: NSCoder) { nil }

    static func normalized(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    func configure(builtin: [String], custom: [String], hovered: Bool, selected: Bool) {
        builtinAliases = builtin
        customAliases = custom
        self.hovered = hovered
        rowSelected = selected
        guard !editing else { return }
        applyContent()
    }

    func beginEditing() {
        guard !editing else { return }
        editing = true
        editor.stringValue = customAliases.joined(separator: ", ")
        editor.isHidden = false
        pill.isHidden = true
        window?.makeFirstResponder(editor)
        if let fieldEditor = editor.currentEditor() {
            fieldEditor.selectedRange = NSRange(location: editor.stringValue.count, length: 0)
        }
    }

    func endEditing(commit: Bool) {
        finish(commit: commit, movesFocus: true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finish(commit: true, movesFocus: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(commit: false)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            endEditing(commit: true)
            return true
        default:
            return false
        }
    }

    private func finish(commit: Bool, movesFocus: Bool) {
        guard editing else { return }
        editing = false
        let text = editor.stringValue
        editor.isHidden = true
        pill.isHidden = false
        applyContent()
        if movesFocus, let table = enclosingTable, window?.firstResponder !== table {
            window?.makeFirstResponder(table)
        }
        guard commit else { return }
        onCommit?(Self.normalized(text))
    }

    private var showsPlaceholder: Bool {
        customAliases.isEmpty && (hovered || rowSelected)
    }

    private var enclosingTable: NSTableView? {
        var view = superview
        while let current = view {
            if let table = current as? NSTableView { return table }
            view = current.superview
        }
        return nil
    }

    private func applyContent() {
        let builtinText = builtinAliases.joined(separator: ", ")
        let trailingComma = !customAliases.isEmpty || hovered
        builtinLabel.stringValue = builtinText.isEmpty || !trailingComma ? builtinText : builtinText + ","
        builtinLabel.isHidden = builtinText.isEmpty
        if customAliases.isEmpty {
            customLabel.stringValue = showsPlaceholder ? "Add alias" : ""
            customLabel.isHidden = !showsPlaceholder
        } else {
            customLabel.stringValue = customAliases.joined(separator: ", ")
            customLabel.isHidden = false
        }
        applyStyle()
    }

    private func applyStyle() {
        let emphasized = backgroundStyle == .emphasized
        let ink = SelectionPalette.ink(effectiveAppearance)
        let muted = emphasized ? ink.tertiary : NSColor.tertiaryLabelColor
        builtinLabel.textColor = muted
        if showsPlaceholder {
            customLabel.textColor = muted
        } else {
            customLabel.textColor = emphasized ? ink.primary : .labelColor
        }
        if showsPlaceholder {
            pill.fill = emphasized ? nil : NSColor.labelColor.withAlphaComponent(0.05)
        } else {
            pill.fill = nil
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    private func buildLayout() {
        pill.translatesAutoresizingMaskIntoConstraints = false

        for label in [builtinLabel, customLabel] {
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingTail
            label.isSelectable = false
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        builtinLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(249), for: .horizontal)
        customLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)

        labels.orientation = .horizontal
        labels.alignment = .centerY
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.addArrangedSubview(builtinLabel)
        labels.addArrangedSubview(customLabel)

        editor.font = .systemFont(ofSize: 13)
        editor.controlSize = .small
        editor.isBordered = true
        editor.isBezeled = true
        editor.bezelStyle = .roundedBezel
        editor.drawsBackground = true
        editor.backgroundColor = .textBackgroundColor
        editor.focusRingType = .exterior
        editor.usesSingleLineMode = true
        editor.lineBreakMode = .byClipping
        editor.delegate = self
        editor.isHidden = true
        editor.translatesAutoresizingMaskIntoConstraints = false
        if let cell = editor.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = true
        }

        addSubview(pill)
        pill.addSubview(labels)
        addSubview(editor)

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 22),
            labels.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: pill.trailingAnchor, constant: -6),
            labels.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            editor.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            editor.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            editor.heightAnchor.constraint(equalToConstant: 24),
        ])
    }
}

@MainActor
private final class AliasPill: NSView {
    var fill: NSColor? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let fill else { return }
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}
