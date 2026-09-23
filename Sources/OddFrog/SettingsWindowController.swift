import AppKit
import OddFrogCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private enum Column {
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let name = NSUserInterfaceItemIdentifier("name")
        static let kind = NSUserInterfaceItemIdentifier("kind")
        static let aliases = NSUserInterfaceItemIdentifier("aliases")
    }

    let pluginsPane = PluginsPane()
    var onChange: ((OddFrogCore.Settings) -> Void)?
    var onApplyLink: ((CommandItem?, LinkDraft?) throws -> [CommandItem])?
    var onHotkey: ((Hotkey) -> Void)?
    var links: [CommandItem] = []

    private let icons: IconCache
    private let linkManager = LinkManagerController()
    private let splitController = NSSplitViewController()
    private let sidebar = SettingsSidebarController()
    private let paneController = NSTabViewController()
    private let general = GeneralPaneModel()
    private let itemTable = ItemTable()
    private let itemScroll = NSScrollView()
    private let filterField = NSSearchField()
    private let itemsHelper = SettingsLayout.helper("Grey aliases are built in. Click a cell to add your own; Return saves.")
    private let itemsEmptyLabel = SettingsLayout.helper()

    private var currentPane = SettingsPane.general
    private var selectedItemRow = -1
    private weak var editingAliasCell: AliasCellView?

    private(set) var settings = OddFrogCore.Settings.empty
    private var allItems: [LauncherItem] = []
    private var visibleItems: [LauncherItem] = []

    init(icons: IconCache) {
        self.icons = icons
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        icons.observeLoads { [weak self] _ in
            guard let self, window.isVisible, !visibleItems.isEmpty else { return }
            let column = itemTable.column(withIdentifier: Column.name)
            guard column >= 0 else { return }
            itemTable.reloadData(forRowIndexes: IndexSet(integersIn: 0..<visibleItems.count), columnIndexes: IndexSet(integer: column))
        }
    }

    required init?(coder: NSCoder) { nil }

    func present(settings: OddFrogCore.Settings, items: [LauncherItem], hotkey: Hotkey, focusing id: String? = nil) {
        self.settings = settings
        allItems = items
        showHotkey(hotkey)
        general.refreshLogin()
        let target = id.flatMap { targetID in items.first { $0.id == targetID } }
        filterField.stringValue = target?.title ?? ""
        applyFilter()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        if let target, let row = visibleItems.firstIndex(where: { $0.id == target.id }) {
            showPane(.items)
            itemTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            itemTable.scrollRowToVisible(row)
            window?.initialFirstResponder = itemTable
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(itemTable)
            layoutColumns()
            beginAliasEdit(row: row)
        } else {
            window?.initialFirstResponder = currentPane == .items ? filterField : nil
            window?.makeKeyAndOrderFront(nil)
            if currentPane == .items {
                window?.makeFirstResponder(filterField)
            } else {
                sidebar.focus()
            }
            layoutColumns()
        }
    }

    func update(items: [LauncherItem]) {
        guard allItems != items else { return }
        allItems = items
        applyFilter()
    }

    func update(pluginSettings: [PluginSetting]) { settings.plugins = pluginSettings }

    func showHotkey(_ hotkey: Hotkey, note: String? = nil) {
        general.show(hotkey, note: note)
    }

    func select(_ pane: SettingsPane) { showPane(pane) }

    func manageLinks() {
        guard let window else { return }
        endAliasEdit(commit: true)
        linkManager.onApply = onApplyLink
        linkManager.present(links: links, for: window)
    }

    private func buildContent() {
        guard let window else { return }
        window.delegate = self
        sidebar.onSelect = { [weak self] pane in self?.showPane(pane) }
        general.onHotkey = { [weak self] hotkey in self?.onHotkey?(hotkey) }

        paneController.tabStyle = .unspecified
        let generalHost = NSHostingController(rootView: GeneralPaneView(model: general))
        generalHost.sizingOptions = []
        paneController.addChild(generalHost)
        paneController.addChild(hosted(makeItemsPane()))
        paneController.addChild(hosted(pluginsPane))

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(NSSplitViewItem(viewController: paneController))

        window.contentViewController = splitController
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 760, height: 560)
        window.center()
        showPane(.general)
    }

    private func hosted(_ content: NSView) -> NSViewController {
        let controller = NSViewController()
        let root = NSView()
        controller.view = root
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.layoutMarginsGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: root.layoutMarginsGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.layoutMarginsGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.layoutMarginsGuide.bottomAnchor),
        ])
        return controller
    }

    private func makeItemsPane() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        itemsHelper.lineBreakMode = .byTruncatingTail
        itemsHelper.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        filterField.placeholderString = "Filter"
        filterField.controlSize = .regular
        filterField.font = .systemFont(ofSize: 13)
        filterField.delegate = self
        filterField.translatesAutoresizingMaskIntoConstraints = false

        for (id, columnTitle, width) in [
            (Column.enabled, "", CGFloat(32)),
            (Column.name, "Item", CGFloat(260)),
            (Column.kind, "Kind", CGFloat(64)),
            (Column.aliases, "Aliases", CGFloat(200)),
        ] {
            let column = NSTableColumn(identifier: id)
            column.title = columnTitle
            column.width = width
            column.minWidth = id == Column.enabled ? 32 : 60
            column.resizingMask = id == Column.name || id == Column.aliases ? .autoresizingMask : []
            if id == Column.enabled {
                column.maxWidth = 32
                column.headerToolTip = "Show in launcher"
            }
            if id == Column.kind { column.maxWidth = 64 }
            if id == Column.aliases { column.headerToolTip = "Comma separated. Built-in aliases from config are kept." }
            itemTable.addTableColumn(column)
        }
        itemTable.dataSource = self
        itemTable.delegate = self
        itemTable.rowHeight = 36
        itemTable.intercellSpacing = NSSize(width: 0, height: 0)
        itemTable.usesAlternatingRowBackgroundColors = false
        itemTable.allowsEmptySelection = true
        itemTable.backgroundColor = .clear
        itemTable.style = .plain
        itemTable.columnAutoresizingStyle = .noColumnAutoresizing
        itemTable.target = self
        itemTable.action = #selector(itemTableClicked)
        itemTable.onReturn = { [weak self] in
            guard let self else { return }
            beginAliasEdit(row: itemTable.selectedRow)
        }

        itemScroll.documentView = itemTable
        itemScroll.drawsBackground = false
        itemScroll.borderType = .noBorder
        itemScroll.hasVerticalScroller = true
        itemScroll.autohidesScrollers = true
        itemScroll.translatesAutoresizingMaskIntoConstraints = false

        itemsEmptyLabel.font = .systemFont(ofSize: 13)
        itemsEmptyLabel.alignment = .center
        itemsEmptyLabel.isHidden = true

        let box = GroupBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(itemScroll)
        box.addSubview(itemsEmptyLabel)
        container.addSubview(filterField)
        container.addSubview(box)
        container.addSubview(itemsHelper)

        let boxHeight = box.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        boxHeight.priority = NSLayoutConstraint.Priority(999)

        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: container.topAnchor),
            filterField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            filterField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            filterField.heightAnchor.constraint(equalToConstant: 22),
            box.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 12),
            box.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            boxHeight,
            itemsHelper.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 12),
            itemsHelper.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            itemsHelper.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            itemsHelper.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            itemScroll.topAnchor.constraint(equalTo: box.topAnchor),
            itemScroll.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            itemScroll.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
            itemScroll.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            itemsEmptyLabel.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            itemsEmptyLabel.centerYAnchor.constraint(equalTo: box.centerYAnchor, constant: -12),
        ])
        return container
    }

    private func showPane(_ pane: SettingsPane) {
        if currentPane == .items, pane != .items { endAliasEdit(commit: true) }
        sidebar.focus()
        currentPane = pane
        sidebar.selected = pane
        paneController.selectedTabViewItemIndex = pane.rawValue
        window?.title = pane.title
        guard pane == .items else { return }
        layoutColumns()
        window?.makeFirstResponder(filterField)
    }

    private func layoutColumns() {
        window?.contentView?.layoutSubtreeIfNeeded()
        let columns = Dictionary(uniqueKeysWithValues: itemTable.tableColumns.map { ($0.identifier, $0) })
        guard let name = columns[Column.name], let aliases = columns[Column.aliases] else { return }
        let available = max(160, itemScroll.contentSize.width - 16 - 32 - 64)
        name.width = available * 2 / 3.4
        aliases.width = available * 1.4 / 3.4
    }

    private func applyFilter() {
        endAliasEdit(commit: false)
        let raw = filterField.stringValue.trimmingCharacters(in: .whitespaces)
        let query = raw.lowercased()
        visibleItems = query.isEmpty ? allItems : allItems.filter {
            $0.title.lowercased().contains(query) || $0.aliases.contains { $0.contains(query) } || ($0.kindLabel ?? "App").lowercased().contains(query)
        }
        itemTable.reloadData()
        selectedItemRow = itemTable.selectedRow
        itemsEmptyLabel.stringValue = "No items match “\(raw)”."
        itemsEmptyLabel.isHidden = !(visibleItems.isEmpty && !raw.isEmpty)
    }

    private var aliasColumnIndex: Int? {
        itemTable.tableColumns.firstIndex { $0.identifier == Column.aliases }
    }

    private func aliasCell(row: Int, makeIfNecessary: Bool) -> AliasCellView? {
        guard row >= 0, row < visibleItems.count, let column = aliasColumnIndex else { return nil }
        return itemTable.view(atColumn: column, row: row, makeIfNecessary: makeIfNecessary) as? AliasCellView
    }

    private func refreshAliasCell(row: Int) {
        guard let cell = aliasCell(row: row, makeIfNecessary: false), !cell.isEditingAliases else { return }
        configureAliasCell(cell, row: row)
    }

    private func configureAliasCell(_ cell: AliasCellView, row: Int) {
        let item = visibleItems[row]
        let custom = settings.override(for: item.id)?.aliases ?? []
        let builtin = item.aliases.filter { !custom.contains($0) }
        let hovered = (itemTable.rowView(atRow: row, makeIfNecessary: false) as? HoverRowView)?.isHovered ?? false
        cell.configure(builtin: builtin, custom: custom, hovered: hovered, selected: itemTable.selectedRow == row)
        cell.onCommit = { [weak self, weak cell] aliases in
            guard let self, let cell else { return }
            let index = itemTable.row(for: cell)
            guard index >= 0, index < visibleItems.count else { return }
            let target = visibleItems[index]
            var override = settings.override(for: target.id) ?? ItemOverride(id: target.id)
            override.aliases = aliases
            settings.setOverride(override)
            commit()
            refreshAliasCell(row: index)
        }
    }

    private func beginAliasEdit(row: Int) {
        endAliasEdit(commit: true)
        guard row >= 0, row < visibleItems.count else { return }
        itemTable.scrollRowToVisible(row)
        guard let cell = aliasCell(row: row, makeIfNecessary: true) else { return }
        editingAliasCell = cell
        cell.beginEditing()
    }

    private func endAliasEdit(commit shouldCommit: Bool) {
        guard let cell = editingAliasCell else { return }
        editingAliasCell = nil
        cell.endEditing(commit: shouldCommit)
    }

    @objc private func itemTableClicked() {
        let row = itemTable.clickedRow
        guard row >= 0, itemTable.clickedColumn == aliasColumnIndex else { return }
        beginAliasEdit(row: row)
    }

    private func commit() {
        onChange?(settings)
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < visibleItems.count else { return }
        let item = visibleItems[row]
        var override = settings.override(for: item.id) ?? ItemOverride(id: item.id)
        override.enabled = sender.state == .on
        settings.setOverride(override)
        commit()
        if let column = itemTable.tableColumns.firstIndex(where: { $0.identifier == Column.name }) {
            itemTable.reloadData(forRowIndexes: [row], columnIndexes: [column])
        }
    }

    func windowDidResize(_ notification: Notification) {
        layoutColumns()
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === filterField { applyFilter() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleItems.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView === itemTable else { return }
        let previous = selectedItemRow
        selectedItemRow = itemTable.selectedRow
        if previous >= 0 { refreshAliasCell(row: previous) }
        if selectedItemRow >= 0 { refreshAliasCell(row: selectedItemRow) }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = HoverRowView()
        rowView.onHoverChange = { [weak self, weak rowView] _ in
            guard let self, let rowView else { return }
            let index = itemTable.row(for: rowView)
            guard index >= 0 else { return }
            refreshAliasCell(row: index)
        }
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let item = visibleItems[row]
        let override = settings.override(for: item.id)
        switch id {
        case Column.enabled:
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
                let host = NSTableCellView()
                host.identifier = id
                let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
                b.toolTip = "Show in launcher"
                b.translatesAutoresizingMaskIntoConstraints = false
                host.addSubview(b)
                NSLayoutConstraint.activate([
                    b.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                    b.centerYAnchor.constraint(equalTo: host.centerYAnchor),
                ])
                return host
            }()
            guard let button = cell.subviews.first as? NSButton else { return cell }
            button.tag = row
            button.state = (override?.enabled ?? true) ? .on : .off
            return cell
        case Column.name:
            let enabled = override?.enabled ?? true
            let cell = textCell(tableView, id: id, withIcon: true)
            cell.imageView?.image = icons.icon(for: item, size: 20)
            cell.imageView?.alphaValue = enabled ? 1 : 0.45
            cell.textField?.font = .systemFont(ofSize: 13)
            cell.textField?.stringValue = item.title
            cell.textField?.textColor = enabled ? .labelColor : .secondaryLabelColor
            return cell
        case Column.kind:
            let cell = textCell(tableView, id: id)
            cell.textField?.font = .systemFont(ofSize: 13)
            cell.textField?.stringValue = item.kindLabel ?? "App"
            cell.textField?.textColor = (override?.enabled ?? true) ? .secondaryLabelColor : .tertiaryLabelColor
            return cell
        case Column.aliases:
            let cell = (tableView.makeView(withIdentifier: AliasCellView.identifier, owner: nil) as? AliasCellView) ?? AliasCellView(frame: .zero)
            cell.toolTip = "Comma separated. Built-in aliases from config are kept."
            configureAliasCell(cell, row: row)
            return cell
        default:
            return nil
        }
    }

    private func textCell(_ tableView: NSTableView, id: NSUserInterfaceItemIdentifier, withIcon: Bool = false) -> NSTableCellView {
        if let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView { return cell }
        let cell = NSTableCellView()
        cell.identifier = id
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        var leading = cell.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: -4)
        if withIcon {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 20),
                image.heightAnchor.constraint(equalToConstant: 20),
            ])
            leading = field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8)
        }
        NSLayoutConstraint.activate([
            leading,
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
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
