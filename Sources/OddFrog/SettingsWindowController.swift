import AppKit
import OddFrogCore
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate {
    private enum Column {
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let name = NSUserInterfaceItemIdentifier("name")
        static let kind = NSUserInterfaceItemIdentifier("kind")
        static let aliases = NSUserInterfaceItemIdentifier("aliases")
        static let folder = NSUserInterfaceItemIdentifier("folder")
    }

    private let icons: IconCache
    private let folderTable = NSTableView()
    private let itemTable = NSTableView()
    private let watchCheckbox = NSButton(checkboxWithTitle: "Watch folders for changes", target: nil, action: nil)
    private let filterField = NSSearchField()
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let hotkeyRecorder = HotkeyRecorder()
    private let hotkeyNote = NSTextField(labelWithString: "")
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let loginNote = NSTextField(labelWithString: "")

    private(set) var settings = Settings.empty
    private var allItems: [LauncherItem] = []
    private var visibleItems: [LauncherItem] = []
    var onChange: ((Settings) -> Void)?
    var onHotkey: ((Hotkey) -> Void)?

    init(icons: IconCache) {
        self.icons = icons
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Odd Frog Settings"
        window.minSize = NSSize(width: 560, height: 420)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func present(settings: Settings, items: [LauncherItem], hotkey: Hotkey) {
        self.settings = settings
        self.allItems = items
        showHotkey(hotkey)
        refreshLogin()
        reloadFolders()
        applyFilter()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(items: [LauncherItem]) {
        allItems = items
        applyFilter()
    }

    func refreshLogin() {
        let status = LoginItem.status
        loginCheckbox.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginCheckbox.isEnabled = status != .notFound
        switch status {
        case .requiresApproval:
            loginNote.stringValue = "Waiting for approval in System Settings → General → Login Items."
        case .notFound:
            loginNote.stringValue = "Available after the app is installed in Applications (make install)."
        default:
            loginNote.stringValue = ""
        }
    }

    func showHotkey(_ hotkey: Hotkey, note: String? = nil) {
        hotkeyRecorder.hotkey = hotkey
        hotkeyNote.stringValue = note ?? "Click, then press the new combination."
        hotkeyNote.textColor = note == nil ? .secondaryLabelColor : .systemRed
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let hotkeyLabel = label("Hotkey", bold: true)
        hotkeyRecorder.translatesAutoresizingMaskIntoConstraints = false
        hotkeyRecorder.onRecord = { [weak self] hotkey in self?.onHotkey?(hotkey) }
        hotkeyNote.font = .systemFont(ofSize: 11)
        hotkeyNote.textColor = .secondaryLabelColor
        hotkeyNote.lineBreakMode = .byTruncatingTail
        let hotkeyRow = NSStackView(views: [hotkeyRecorder, hotkeyNote])
        hotkeyRow.orientation = .horizontal
        hotkeyRow.spacing = 10
        hotkeyRow.alignment = .centerY

        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        loginNote.font = .systemFont(ofSize: 11)
        loginNote.textColor = .secondaryLabelColor
        loginNote.lineBreakMode = .byTruncatingTail
        let loginRow = NSStackView(views: [loginCheckbox, loginNote])
        loginRow.orientation = .horizontal
        loginRow.spacing = 10
        loginRow.alignment = .centerY

        let foldersLabel = label("Script folders", bold: true)
        let foldersHint = label("Executable scripts here appear in the launcher. Raycast metadata is optional.", bold: false)
        foldersHint.textColor = .secondaryLabelColor

        let folderColumn = NSTableColumn(identifier: Column.folder)
        folderColumn.title = "Folder"
        folderTable.addTableColumn(folderColumn)
        folderTable.headerView = nil
        folderTable.dataSource = self
        folderTable.delegate = self
        folderTable.rowHeight = 22
        folderTable.allowsEmptySelection = true
        let folderScroll = scroll(folderTable)

        let addButton = NSButton(title: "Add…", target: self, action: #selector(addFolder))
        removeButton.target = self
        removeButton.action = #selector(removeFolder)
        removeButton.isEnabled = false
        watchCheckbox.target = self
        watchCheckbox.action = #selector(toggleWatch)
        let folderButtons = NSStackView(views: [addButton, removeButton, watchCheckbox])
        folderButtons.orientation = .horizontal
        folderButtons.spacing = 8

        let itemsLabel = label("Items", bold: true)
        filterField.placeholderString = "Filter"
        filterField.delegate = self
        let itemsHeader = NSStackView(views: [itemsLabel, filterField])
        itemsHeader.orientation = .horizontal
        itemsHeader.distribution = .fill
        filterField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        itemsLabel.setContentHuggingPriority(.required, for: .horizontal)

        for (id, title, width) in [
            (Column.enabled, "", CGFloat(28)),
            (Column.name, "Item", CGFloat(260)),
            (Column.kind, "Kind", CGFloat(80)),
            (Column.aliases, "Aliases", CGFloat(200)),
        ] {
            let column = NSTableColumn(identifier: id)
            column.title = title
            column.width = width
            column.minWidth = id == Column.enabled ? 28 : 60
            if id == Column.enabled {
                column.maxWidth = 28
                column.headerToolTip = "Show in launcher"
            }
            if id == Column.aliases { column.headerToolTip = "Comma separated. Built-in aliases from config are kept." }
            itemTable.addTableColumn(column)
        }
        itemTable.dataSource = self
        itemTable.delegate = self
        itemTable.rowHeight = 28
        itemTable.usesAlternatingRowBackgroundColors = true
        itemTable.allowsEmptySelection = true
        itemTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let itemScroll = scroll(itemTable)

        let stack = NSStackView(views: [hotkeyLabel, hotkeyRow, loginRow, foldersLabel, foldersHint, folderScroll, folderButtons, itemsHeader, itemScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(16, after: loginRow)
        stack.setCustomSpacing(16, after: folderButtons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            folderScroll.heightAnchor.constraint(equalToConstant: 60),
            hotkeyRecorder.widthAnchor.constraint(equalToConstant: 160),
            hotkeyRecorder.heightAnchor.constraint(equalToConstant: 24),
            folderScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            foldersHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            itemsHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
            itemScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func label(_ text: String, bold: Bool) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 11)
        field.isSelectable = false
        return field
    }

    private func scroll(_ table: NSTableView) -> NSScrollView {
        let view = NSScrollView()
        view.documentView = table
        view.hasVerticalScroller = true
        view.borderType = .bezelBorder
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func reloadFolders() {
        folderTable.reloadData()
        watchCheckbox.state = settings.scripts.watch ? .on : .off
        removeButton.isEnabled = folderTable.selectedRow >= 0
    }

    private func applyFilter() {
        let query = filterField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        visibleItems = query.isEmpty ? allItems : allItems.filter {
            $0.title.lowercased().contains(query) || $0.aliases.contains { $0.contains(query) } || ($0.kindLabel ?? "App").lowercased().contains(query)
        }
        itemTable.reloadData()
    }

    private func commit() {
        onChange?(settings)
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            for url in panel.urls {
                var path = url.path
                if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
                if !settings.scripts.folders.contains(path) { settings.scripts.folders.append(path) }
            }
            reloadFolders()
            commit()
        }
    }

    @objc private func removeFolder() {
        let row = folderTable.selectedRow
        guard row >= 0, row < settings.scripts.folders.count else { return }
        settings.scripts.folders.remove(at: row)
        reloadFolders()
        commit()
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.toggle()
        } catch {
            loginNote.stringValue = error.localizedDescription
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated { self.refreshLogin() }
        }
        refreshLogin()
    }

    @objc private func toggleWatch() {
        settings.scripts.watch = watchCheckbox.state == .on
        commit()
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < visibleItems.count else { return }
        let item = visibleItems[row]
        var override = settings.override(for: item.id) ?? ItemOverride(id: item.id)
        override.enabled = sender.state == .on
        settings.setOverride(override)
        commit()
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === filterField { applyFilter() }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field.identifier == Column.aliases else { return }
        let row = field.tag
        guard row >= 0, row < visibleItems.count else { return }
        let item = visibleItems[row]
        let aliases = field.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        var override = settings.override(for: item.id) ?? ItemOverride(id: item.id)
        override.aliases = aliases
        settings.setOverride(override)
        commit()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === folderTable ? settings.scripts.folders.count : visibleItems.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if notification.object as? NSTableView === folderTable {
            removeButton.isEnabled = folderTable.selectedRow >= 0
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        if tableView === folderTable {
            let cell = textCell(tableView, id: id)
            cell.textField?.stringValue = settings.scripts.folders[row]
            return cell
        }
        let item = visibleItems[row]
        let override = settings.override(for: item.id)
        switch id {
        case Column.enabled:
            let button = (tableView.makeView(withIdentifier: id, owner: nil) as? NSButton) ?? {
                let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
                b.identifier = id
                b.toolTip = "Show in launcher"
                return b
            }()
            button.tag = row
            button.state = (override?.enabled ?? true) ? .on : .off
            return button
        case Column.name:
            let cell = textCell(tableView, id: id, withIcon: true)
            cell.imageView?.image = icons.icon(for: item)
            cell.textField?.stringValue = item.title
            cell.textField?.textColor = (override?.enabled ?? true) ? .labelColor : .tertiaryLabelColor
            return cell
        case Column.kind:
            let cell = textCell(tableView, id: id)
            cell.textField?.stringValue = item.kindLabel ?? "App"
            cell.textField?.textColor = .secondaryLabelColor
            return cell
        case Column.aliases:
            let cell = textCell(tableView, id: id)
            let field = cell.textField!
            field.isEditable = true
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .default
            field.delegate = self
            field.identifier = Column.aliases
            field.tag = row
            field.toolTip = "Comma separated"
            field.stringValue = (override?.aliases ?? []).joined(separator: ", ")
            let builtIn = item.aliases.filter { !(override?.aliases ?? []).contains($0) }
            field.placeholderString = builtIn.isEmpty ? "" : "built-in: " + builtIn.joined(separator: ", ")
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
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 20),
                image.heightAnchor.constraint(equalToConstant: 20),
            ])
            leading = field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6)
        }
        NSLayoutConstraint.activate([
            leading,
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
