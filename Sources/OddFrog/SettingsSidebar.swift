import AppKit

enum SettingsPane: Int, CaseIterable {
    case general
    case folders
    case items

    var title: String {
        switch self {
        case .general: return "General"
        case .folders: return "Script Folders"
        case .items: return "Items"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .folders: return "folder.fill"
        case .items: return "square.grid.2x2.fill"
        }
    }

    var tint: NSColor {
        switch self {
        case .general: return .systemGray
        case .folders: return .systemTeal
        case .items: return .controlAccentColor
        }
    }
}

@MainActor
final class Hairline: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        bounds.fill()
    }
}

@MainActor
final class SettingsSidebar: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((SettingsPane) -> Void)?

    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var suppressesCallback = false

    var selected: SettingsPane {
        get { SettingsPane(rawValue: table.selectedRow) ?? .general }
        set {
            guard table.selectedRow != newValue.rawValue else { return }
            suppressesCallback = true
            table.selectRowIndexes(IndexSet(integer: newValue.rawValue), byExtendingSelection: false)
            suppressesCallback = false
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { nil }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        effect.translatesAutoresizingMaskIntoConstraints = false

        let separator = Hairline()
        separator.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 36
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.selectionHighlightStyle = .none
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.backgroundColor = .clear
        table.style = .plain
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(effect)
        addSubview(scroll)
        addSubview(separator)

        NSLayoutConstraint.activate([
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 0.5),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 56),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
            scroll.heightAnchor.constraint(equalToConstant: 36 * CGFloat(SettingsPane.allCases.count) + 2 * CGFloat(SettingsPane.allCases.count - 1)),
        ])

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        SettingsPane.allCases.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SidebarRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let pane = SettingsPane(rawValue: row) else { return nil }
        return SidebarCellView(pane: pane)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressesCallback, let pane = SettingsPane(rawValue: table.selectedRow) else { return }
        onSelect?(pane)
    }
}

@MainActor
private final class SidebarRowView: NSTableRowView {
    override var isSelected: Bool {
        didSet {
            needsDisplay = true
            applySelection()
        }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        applySelection()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isSelected else { return }
        SelectionPalette.fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }

    private func applySelection() {
        for case let cell as SidebarCellView in subviews { cell.isRowSelected = isSelected }
    }
}

@MainActor
private final class SidebarCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    var isRowSelected = false {
        didSet { applyStyle() }
    }

    init(pane: SettingsPane) {
        super.init(frame: .zero)
        let tile = IconTile(color: pane.tint, symbol: pane.symbol, side: 24, radius: 6, pointSize: 13)
        label.stringValue = pane.title
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tile)
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyStyle()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    private func applyStyle() {
        label.textColor = isRowSelected ? SelectionPalette.ink(effectiveAppearance).primary : .labelColor
    }
}
