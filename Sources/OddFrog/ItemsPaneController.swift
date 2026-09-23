import AppKit
import OddFrogCore

@MainActor
final class ItemsPaneController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private enum Column {
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let name = NSUserInterfaceItemIdentifier("name")
        static let kind = NSUserInterfaceItemIdentifier("kind")
        static let builtin = NSUserInterfaceItemIdentifier("builtin")
        static let aliases = NSUserInterfaceItemIdentifier("aliases")
    }

    private static let iconSize: CGFloat = 16

    var settings = Settings.empty
    var onChange: ((Settings) -> Void)?

    private let icons: IconCache
    private let table = ItemTable()
    private let filterField = NSSearchField()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var allItems: [LauncherItem] = []
    private var visibleItems: [LauncherItem] = []
    private var discardingEdit = false

    init(icons: IconCache) {
        self.icons = icons
        super.init(nibName: nil, bundle: nil)
        filterField.placeholderString = "Filter"
        filterField.delegate = self
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true
        configureTable()
        icons.observeLoads { [weak self] _ in
            guard let self, !visibleItems.isEmpty else { return }
            let column = table.column(withIdentifier: Column.name)
            guard column >= 0 else { return }
            table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<visibleItems.count), columnIndexes: IndexSet(integer: column))
        }
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let helper = NSTextField(wrappingLabelWithString: "Click an Aliases cell or press Return to add your own aliases, separated by commas. Return saves, Esc cancels.")
        helper.font = .preferredFont(forTextStyle: .subheadline)
        helper.textColor = .secondaryLabelColor
        helper.translatesAutoresizingMaskIntoConstraints = false

        filterField.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(filterField)
        root.addSubview(scroll)
        root.addSubview(emptyLabel)
        root.addSubview(helper)

        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: root.layoutMarginsGuide.topAnchor),
            filterField.leadingAnchor.constraint(equalTo: root.layoutMarginsGuide.leadingAnchor),
            filterField.trailingAnchor.constraint(equalTo: root.layoutMarginsGuide.trailingAnchor),

            scroll.topAnchor.constraint(equalToSystemSpacingBelow: filterField.bottomAnchor, multiplier: 1),
            scroll.leadingAnchor.constraint(equalTo: root.layoutMarginsGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.layoutMarginsGuide.trailingAnchor),

            helper.topAnchor.constraint(equalToSystemSpacingBelow: scroll.bottomAnchor, multiplier: 1),
            helper.leadingAnchor.constraint(equalTo: root.layoutMarginsGuide.leadingAnchor),
            helper.trailingAnchor.constraint(equalTo: root.layoutMarginsGuide.trailingAnchor),
            helper.bottomAnchor.constraint(equalTo: root.layoutMarginsGuide.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])

        view = root
    }

    private func configureTable() {
        table.style = .inset
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(tableClicked)
        table.onReturn = { [weak self] in
            guard let self else { return }
            beginEditing(row: table.selectedRow)
        }

        let enabled = NSTableColumn(identifier: Column.enabled)
        enabled.title = ""
        enabled.headerToolTip = "Show in launcher"
        let checkWidth = NSButton(checkboxWithTitle: "", target: nil, action: nil).fittingSize.width
        enabled.width = checkWidth
        enabled.minWidth = checkWidth
        enabled.maxWidth = checkWidth
        enabled.resizingMask = []
        table.addTableColumn(enabled)

        addColumn(Column.name, title: "Item", width: 160)
        addColumn(Column.kind, title: "Kind", width: 60)
        addColumn(Column.builtin, title: "Built-in Aliases", width: 90)

        let aliases = NSTableColumn(identifier: Column.aliases)
        aliases.title = "Aliases"
        aliases.width = 90
        aliases.headerToolTip = "Comma separated. Built-in aliases from config are kept."
        table.addTableColumn(aliases)
    }

    private func addColumn(_ id: NSUserInterfaceItemIdentifier, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: id)
        column.title = title
        column.width = width
        table.addTableColumn(column)
    }

    func show(items: [LauncherItem], revealing id: String?) -> Bool {
        allItems = items
        let target = id.flatMap { targetID in items.first { $0.id == targetID } }
        filterField.stringValue = target?.title ?? ""
        applyFilter()
        guard let id else { return false }
        return visibleItems.contains { $0.id == id }
    }

    func update(items: [LauncherItem]) {
        guard allItems != items else { return }
        allItems = items
        applyFilter()
    }

    func focusFilter() {
        filterField.window?.makeFirstResponder(filterField)
    }

    func edit(itemID: String) {
        guard let row = visibleItems.firstIndex(where: { $0.id == itemID }) else { return }
        table.window?.makeFirstResponder(table)
        beginEditing(row: row)
    }

    func endEditing(commit: Bool) {
        guard let field = editedAliasField else { return }
        if commit {
            table.window?.makeFirstResponder(table)
        } else {
            discardingEdit = true
            field.abortEditing()
            discardingEdit = false
            table.window?.makeFirstResponder(table)
        }
    }

    private func applyFilter() {
        endEditing(commit: false)
        let raw = filterField.stringValue.trimmingCharacters(in: .whitespaces)
        let query = raw.lowercased()
        visibleItems = query.isEmpty ? allItems : allItems.filter {
            $0.title.lowercased().contains(query) || $0.aliases.contains { $0.contains(query) } || ($0.kindLabel ?? "App").lowercased().contains(query)
        }
        table.reloadData()
        emptyLabel.stringValue = "No items match “\(raw)”."
        emptyLabel.isHidden = !(visibleItems.isEmpty && !raw.isEmpty)
    }

    private static func normalized(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private var editedAliasField: NSTextField? {
        guard let editor = table.window?.firstResponder as? NSTextView, editor.isFieldEditor,
              let field = editor.delegate as? NSTextField, field.isDescendant(of: table) else { return nil }
        return field
    }

    private func beginEditing(row: Int) {
        guard row >= 0, row < visibleItems.count else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        table.editColumn(table.column(withIdentifier: Column.aliases), row: row, with: nil, select: true)
    }

    @objc private func tableClicked() {
        let row = table.clickedRow
        guard row >= 0, table.clickedColumn == table.column(withIdentifier: Column.aliases) else { return }
        beginEditing(row: row)
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = table.row(for: sender)
        guard row >= 0, row < visibleItems.count else { return }
        let item = visibleItems[row]
        var override = settings.override(for: item.id) ?? ItemOverride(id: item.id)
        override.enabled = sender.state == .on
        settings.setOverride(override)
        onChange?(settings)
        let name = table.column(withIdentifier: Column.name)
        let kind = table.column(withIdentifier: Column.kind)
        guard name >= 0, kind >= 0 else { return }
        table.reloadData(forRowIndexes: [row], columnIndexes: [name, kind])
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn?.identifier else { return nil }
        let cell = tableView.makeView(withIdentifier: column, owner: nil) as? NSTableCellView ?? makeCell(column)
        configure(cell, column: column, row: row)
        return cell
    }

    private func makeCell(_ column: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = column
        switch column {
        case Column.enabled:
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
            button.toolTip = "Show in launcher"
            button.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        default:
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            if column == Column.name {
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(image)
                cell.imageView = image
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: Self.iconSize),
                    image.heightAnchor.constraint(equalToConstant: Self.iconSize),
                    field.leadingAnchor.constraint(equalToSystemSpacingAfter: image.trailingAnchor, multiplier: 1),
                ])
            } else {
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor).isActive = true
            }
            if column == Column.aliases {
                field.isEditable = true
                field.usesSingleLineMode = true
                field.placeholderString = "Add alias"
                field.delegate = self
            }
            NSLayoutConstraint.activate([
                column == Column.aliases
                    ? field.trailingAnchor.constraint(equalTo: cell.trailingAnchor)
                    : field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    private func configure(_ cell: NSTableCellView, column: NSUserInterfaceItemIdentifier, row: Int) {
        let item = visibleItems[row]
        let override = settings.override(for: item.id)
        switch column {
        case Column.enabled:
            guard let button = cell.subviews.first as? NSButton else { return }
            button.state = (override?.enabled ?? true) ? .on : .off
        case Column.name:
            let enabled = override?.enabled ?? true
            cell.imageView?.image = icons.icon(for: item, size: Self.iconSize)
            cell.textField?.stringValue = item.title
            cell.textField?.textColor = enabled ? .labelColor : .secondaryLabelColor
        case Column.kind:
            cell.textField?.stringValue = item.kindLabel ?? "App"
            cell.textField?.textColor = (override?.enabled ?? true) ? .secondaryLabelColor : .tertiaryLabelColor
        case Column.builtin:
            let custom = override?.aliases ?? []
            cell.textField?.stringValue = item.aliases.filter { !custom.contains($0) }.joined(separator: ", ")
            cell.textField?.textColor = .secondaryLabelColor
        case Column.aliases:
            cell.textField?.stringValue = (override?.aliases ?? []).joined(separator: ", ")
        default:
            break
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === filterField { applyFilter() }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !discardingEdit, let field = obj.object as? NSTextField, field !== filterField else { return }
        let row = table.row(for: field)
        guard row >= 0, row < visibleItems.count else { return }
        let item = visibleItems[row]
        let aliases = Self.normalized(field.stringValue)
        field.stringValue = aliases.joined(separator: ", ")
        let stored = settings.override(for: item.id)?.aliases ?? []
        guard aliases != stored else { return }
        var override = settings.override(for: item.id) ?? ItemOverride(id: item.id)
        override.aliases = aliases
        settings.setOverride(override)
        onChange?(settings)
        let builtin = table.column(withIdentifier: Column.builtin)
        guard builtin >= 0 else { return }
        if let cell = table.view(atColumn: builtin, row: row, makeIfNecessary: false) as? NSTableCellView {
            cell.textField?.stringValue = item.aliases.filter { !aliases.contains($0) }.joined(separator: ", ")
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? NSTextField, field !== filterField else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            table.window?.makeFirstResponder(table)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            let row = table.row(for: field)
            if row >= 0, row < visibleItems.count {
                let item = visibleItems[row]
                textView.string = (settings.override(for: item.id)?.aliases ?? []).joined(separator: ", ")
            }
            table.window?.makeFirstResponder(table)
            return true
        default:
            return false
        }
    }
}

@MainActor
private final class ItemTable: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn?()
            return
        }
        super.keyDown(with: event)
    }
}
