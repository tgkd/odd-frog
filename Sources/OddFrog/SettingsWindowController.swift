import AppKit
import OddFrogCore
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private enum Column {
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let name = NSUserInterfaceItemIdentifier("name")
        static let kind = NSUserInterfaceItemIdentifier("kind")
        static let aliases = NSUserInterfaceItemIdentifier("aliases")
        static let folder = NSUserInterfaceItemIdentifier("folder")
    }

    private struct Metrics {
        let padding: CGFloat
        let gap: CGFloat
        let labelColumn: CGFloat
        let formRow: CGFloat
        let folderRow: CGFloat
        let folderBar: CGFloat
        let searchWidth: CGFloat
        let itemsMinHeight: CGFloat
        let showsItemsHelper: Bool

        static let regular = Metrics(
            padding: 20,
            gap: 18,
            labelColumn: 120,
            formRow: 32,
            folderRow: 28,
            folderBar: 32,
            searchWidth: 200,
            itemsMinHeight: 150,
            showsItemsHelper: true
        )

        static let compact = Metrics(
            padding: 16,
            gap: 14,
            labelColumn: 110,
            formRow: 34,
            folderRow: 26,
            folderBar: 30,
            searchWidth: 160,
            itemsMinHeight: 130,
            showsItemsHelper: false
        )
    }

    private let icons: IconCache
    private let folderTable = FolderTable()
    private let folderScroll = NSScrollView()
    private let itemTable = ItemTable()
    private let itemScroll = NSScrollView()
    private let filterField = NSSearchField()
    private let hotkeyRecorder = HotkeyRecorder()
    private let hotkeyHelper = NSTextField(labelWithString: "")
    private let loginSwitch = NSSwitch()
    private let loginStatus = NSTextField(labelWithString: "")
    private let loginButton = NSButton(title: "Open Login Items…", target: nil, action: nil)
    private let addFolderButton = NSButton(title: "+", target: nil, action: nil)
    private let removeFolderButton = NSButton(title: "−", target: nil, action: nil)
    private let watchSwitch = NSSwitch()
    private let folderEmptyLabel = NSTextField(labelWithString: "No script folders yet. Click + to add one.")
    private let itemsHelper = NSTextField(labelWithString: "Grey aliases are built in. Click a cell to add your own; Return saves.")
    private let itemsEmptyLabel = NSTextField(labelWithString: "")

    private var gapConstraints: [NSLayoutConstraint] = []
    private var labelColumnConstraints: [NSLayoutConstraint] = []
    private var formRowConstraints: [NSLayoutConstraint] = []
    private var paddingLeading: NSLayoutConstraint?
    private var paddingTrailing: NSLayoutConstraint?
    private var paddingBottom: NSLayoutConstraint?
    private var folderListHeight: NSLayoutConstraint?
    private var folderBarHeight: NSLayoutConstraint?
    private var searchFieldWidth: NSLayoutConstraint?
    private var itemsBoxHeight: NSLayoutConstraint?
    private var isCompact = false
    private var selectedItemRow = -1
    private weak var editingAliasCell: AliasCellView?

    private(set) var settings = Settings.empty
    private var allItems: [LauncherItem] = []
    private var visibleItems: [LauncherItem] = []
    private var folderCounts: [Int] = []
    var onChange: ((Settings) -> Void)?
    var onHotkey: ((Hotkey) -> Void)?

    init(icons: IconCache) {
        self.icons = icons
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Odd Frog Settings"
        window.minSize = NSSize(width: 560, height: 420)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.center()
        super.init(window: window)
        buildContent()
        icons.observeLoads { [weak self] _ in
            guard let self, window.isVisible else { return }
            itemTable.reloadData()
        }
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
        window?.initialFirstResponder = filterField
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(filterField)
        layoutColumns()
    }

    func update(items: [LauncherItem]) {
        allItems = items
        recomputeFolderCounts()
        folderTable.reloadData()
        applyFilter()
    }

    func refreshLogin() {
        let status = LoginItem.status
        loginSwitch.isEnabled = status != .notFound
        loginButton.isHidden = status != .requiresApproval
        loginStatus.textColor = .secondaryLabelColor
        switch status {
        case .enabled:
            loginSwitch.state = .on
            loginStatus.stringValue = "Odd Frog opens when you log in."
        case .requiresApproval:
            loginSwitch.state = .on
            loginStatus.stringValue = "Waiting for approval in System Settings › Login Items."
            loginStatus.textColor = .systemOrange
        case .notFound:
            loginSwitch.state = .off
            loginStatus.stringValue = "Move Odd Frog to your Applications folder to enable this."
        default:
            loginSwitch.state = .off
            loginStatus.stringValue = ""
        }
    }

    func showHotkey(_ hotkey: Hotkey, note: String? = nil) {
        hotkeyRecorder.hotkey = hotkey
        if let note {
            hotkeyRecorder.conflict = true
            hotkeyHelper.stringValue = note + " Try another combination."
            hotkeyHelper.textColor = .systemRed
        } else {
            hotkeyRecorder.conflict = false
            hotkeyHelper.stringValue = "Click, then press a new combination."
            hotkeyHelper.textColor = .secondaryLabelColor
        }
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        window?.delegate = self

        let general = makeGeneralGroup()
        let folders = makeFoldersGroup()
        let items = makeItemsGroup()
        general.setContentHuggingPriority(.defaultHigh, for: .vertical)
        folders.setContentHuggingPriority(.defaultHigh, for: .vertical)
        items.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        items.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        for group in [general, folders, items] {
            group.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(group)
        }

        let leading = general.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Metrics.regular.padding)
        let trailing = general.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Metrics.regular.padding)
        let bottom = items.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Metrics.regular.padding)
        let foldersGap = folders.topAnchor.constraint(equalTo: general.bottomAnchor, constant: Metrics.regular.gap)
        let itemsGap = items.topAnchor.constraint(equalTo: folders.bottomAnchor, constant: Metrics.regular.gap)
        paddingLeading = leading
        paddingTrailing = trailing
        paddingBottom = bottom
        gapConstraints = [foldersGap, itemsGap]

        NSLayoutConstraint.activate([
            leading,
            trailing,
            bottom,
            foldersGap,
            itemsGap,
            general.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            folders.leadingAnchor.constraint(equalTo: general.leadingAnchor),
            folders.trailingAnchor.constraint(equalTo: general.trailingAnchor),
            items.leadingAnchor.constraint(equalTo: general.leadingAnchor),
            items.trailingAnchor.constraint(equalTo: general.trailingAnchor),
        ])

        apply(Metrics.regular)
    }

    private func makeGeneralGroup() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let title = groupTitle("General")
        let box = GroupBox()
        box.translatesAutoresizingMaskIntoConstraints = false

        hotkeyRecorder.translatesAutoresizingMaskIntoConstraints = false
        hotkeyRecorder.onRecord = { [weak self] hotkey in self?.onHotkey?(hotkey) }
        hotkeyRecorder.onRecordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording {
                hotkeyHelper.stringValue = "Press the keys you want to use."
                hotkeyHelper.textColor = .secondaryLabelColor
            } else if !hotkeyRecorder.conflict {
                hotkeyHelper.stringValue = "Click, then press a new combination."
                hotkeyHelper.textColor = .secondaryLabelColor
            }
        }
        style(helper: hotkeyHelper)
        hotkeyHelper.stringValue = "Click, then press a new combination."
        let shortcutControl = NSStackView(views: [hotkeyRecorder, hotkeyHelper])
        shortcutControl.orientation = .horizontal
        shortcutControl.spacing = 10
        shortcutControl.alignment = .centerY

        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin)
        style(helper: loginStatus)
        loginButton.target = self
        loginButton.action = #selector(openLoginItems)
        loginButton.bezelStyle = .rounded
        loginButton.controlSize = .small
        loginButton.font = .systemFont(ofSize: 11)
        loginButton.isHidden = true
        let loginControl = NSStackView(views: [loginSwitch, loginStatus, loginButton])
        loginControl.orientation = .horizontal
        loginControl.spacing = 8
        loginControl.alignment = .centerY

        let shortcutRow = formRow(caption: "Shortcut:", control: shortcutControl)
        let loginRow = formRow(caption: "Launch at login:", control: loginControl)
        let divider = hairline()
        box.addSubview(shortcutRow)
        box.addSubview(divider)
        box.addSubview(loginRow)
        container.addSubview(title)
        container.addSubview(box)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            box.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 7),
            box.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            box.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            shortcutRow.topAnchor.constraint(equalTo: box.topAnchor),
            shortcutRow.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            shortcutRow.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            divider.topAnchor.constraint(equalTo: shortcutRow.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            divider.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            loginRow.topAnchor.constraint(equalTo: divider.bottomAnchor),
            loginRow.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            loginRow.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            loginRow.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return container
    }

    private func makeFoldersGroup() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let title = groupTitle("Script Folders")
        let box = GroupBox()
        box.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: Column.folder)
        column.resizingMask = .autoresizingMask
        folderTable.addTableColumn(column)
        folderTable.headerView = nil
        folderTable.dataSource = self
        folderTable.delegate = self
        folderTable.rowHeight = Metrics.regular.folderRow
        folderTable.intercellSpacing = .zero
        folderTable.selectionHighlightStyle = .none
        folderTable.allowsEmptySelection = true
        folderTable.allowsMultipleSelection = false
        folderTable.backgroundColor = .clear
        folderTable.style = .plain
        folderTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        folderTable.onDelete = { [weak self] in self?.removeFolder() }

        folderScroll.documentView = folderTable
        folderScroll.drawsBackground = false
        folderScroll.borderType = .noBorder
        folderScroll.hasVerticalScroller = true
        folderScroll.autohidesScrollers = true
        folderScroll.scrollerStyle = .overlay
        folderScroll.translatesAutoresizingMaskIntoConstraints = false

        style(helper: folderEmptyLabel)
        folderEmptyLabel.font = .systemFont(ofSize: 13)
        folderEmptyLabel.alignment = .center

        let bar = FolderBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        addFolderButton.target = self
        addFolderButton.action = #selector(addFolder)
        removeFolderButton.target = self
        removeFolderButton.action = #selector(removeFolder)
        removeFolderButton.isEnabled = false
        for button in [addFolderButton, removeFolderButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(button)
            button.widthAnchor.constraint(equalToConstant: 26).isActive = true
            button.centerYAnchor.constraint(equalTo: bar.centerYAnchor).isActive = true
        }
        let watchLabel = NSTextField(labelWithString: "Watch for changes")
        watchLabel.font = .systemFont(ofSize: 13)
        watchLabel.translatesAutoresizingMaskIntoConstraints = false
        watchSwitch.target = self
        watchSwitch.action = #selector(toggleWatch)
        watchSwitch.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(watchLabel)
        bar.addSubview(watchSwitch)

        let helper = NSTextField(wrappingLabelWithString: "Executable scripts in these folders appear in the launcher. Raycast script metadata is optional.")
        helper.font = .systemFont(ofSize: 11)
        helper.textColor = .secondaryLabelColor
        helper.isSelectable = false
        helper.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(folderScroll)
        box.addSubview(folderEmptyLabel)
        box.addSubview(bar)
        container.addSubview(title)
        container.addSubview(box)
        container.addSubview(helper)

        let listHeight = folderScroll.heightAnchor.constraint(equalToConstant: Metrics.regular.folderRow)
        let barHeight = bar.heightAnchor.constraint(equalToConstant: Metrics.regular.folderBar)
        folderListHeight = listHeight
        folderBarHeight = barHeight

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            box.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 7),
            box.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            helper.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 6),
            helper.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            helper.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            helper.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            folderScroll.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
            folderScroll.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            folderScroll.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
            listHeight,
            folderEmptyLabel.centerXAnchor.constraint(equalTo: folderScroll.centerXAnchor),
            folderEmptyLabel.centerYAnchor.constraint(equalTo: folderScroll.centerYAnchor),
            bar.topAnchor.constraint(equalTo: folderScroll.bottomAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            barHeight,
            addFolderButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 4),
            removeFolderButton.leadingAnchor.constraint(equalTo: addFolderButton.trailingAnchor, constant: 4),
            watchSwitch.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -6),
            watchSwitch.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            watchLabel.trailingAnchor.constraint(equalTo: watchSwitch.leadingAnchor, constant: -6),
            watchLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            watchLabel.leadingAnchor.constraint(greaterThanOrEqualTo: removeFolderButton.trailingAnchor, constant: 8),
        ])
        return container
    }

    private func makeItemsGroup() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let title = groupTitle("Items")
        style(helper: itemsHelper)
        itemsHelper.lineBreakMode = .byTruncatingTail
        itemsHelper.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        itemsHelper.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        filterField.placeholderString = "Filter"
        filterField.controlSize = .small
        filterField.font = .systemFont(ofSize: 11)
        filterField.delegate = self
        filterField.translatesAutoresizingMaskIntoConstraints = false
        filterField.setContentHuggingPriority(.required, for: .horizontal)

        let header = NSStackView(views: [title, itemsHelper, filterField])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        for (id, columnTitle, width) in [
            (Column.enabled, "", CGFloat(30)),
            (Column.name, "Item", CGFloat(260)),
            (Column.kind, "Kind", CGFloat(68)),
            (Column.aliases, "Aliases", CGFloat(200)),
        ] {
            let column = NSTableColumn(identifier: id)
            column.title = columnTitle
            column.width = width
            column.minWidth = id == Column.enabled ? 30 : 60
            if id == Column.enabled {
                column.maxWidth = 30
                column.headerToolTip = "Show in launcher"
            }
            if id == Column.kind { column.maxWidth = 68 }
            if id == Column.aliases { column.headerToolTip = "Comma separated. Built-in aliases from config are kept." }
            itemTable.addTableColumn(column)
        }
        itemTable.dataSource = self
        itemTable.delegate = self
        itemTable.rowHeight = 28
        itemTable.usesAlternatingRowBackgroundColors = false
        itemTable.allowsEmptySelection = true
        itemTable.backgroundColor = .clear
        itemTable.style = .fullWidth
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

        style(helper: itemsEmptyLabel)
        itemsEmptyLabel.font = .systemFont(ofSize: 13)
        itemsEmptyLabel.alignment = .center
        itemsEmptyLabel.isHidden = true

        let box = GroupBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(itemScroll)
        box.addSubview(itemsEmptyLabel)
        container.addSubview(header)
        container.addSubview(box)

        let boxHeight = box.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.regular.itemsMinHeight)
        boxHeight.priority = NSLayoutConstraint.Priority(999)
        let fieldWidth = filterField.widthAnchor.constraint(equalToConstant: Metrics.regular.searchWidth)
        itemsBoxHeight = boxHeight
        searchFieldWidth = fieldWidth

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            fieldWidth,
            box.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 7),
            box.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            box.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            boxHeight,
            itemScroll.topAnchor.constraint(equalTo: box.topAnchor),
            itemScroll.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            itemScroll.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            itemScroll.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            itemsEmptyLabel.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            itemsEmptyLabel.centerYAnchor.constraint(equalTo: box.centerYAnchor, constant: -12),
        ])
        return container
    }

    private func formRow(caption text: String, control: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let caption = NSTextField(labelWithString: text)
        caption.font = .systemFont(ofSize: 13)
        caption.alignment = .right
        caption.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(caption)
        row.addSubview(control)

        let width = caption.widthAnchor.constraint(equalToConstant: Metrics.regular.labelColumn)
        let height = row.heightAnchor.constraint(equalToConstant: Metrics.regular.formRow)
        labelColumnConstraints.append(width)
        formRowConstraints.append(height)

        NSLayoutConstraint.activate([
            width,
            height,
            caption.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            caption.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: caption.trailingAnchor, constant: 12),
            control.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -14),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 5),
        ])
        return row
    }

    private func groupTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        field.isSelectable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func style(helper field: NSTextField) {
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.isSelectable = false
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
    }

    private func hairline() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func apply(_ metrics: Metrics) {
        paddingLeading?.constant = metrics.padding
        paddingTrailing?.constant = -metrics.padding
        paddingBottom?.constant = -metrics.padding
        for gap in gapConstraints { gap.constant = metrics.gap }
        for constraint in labelColumnConstraints { constraint.constant = metrics.labelColumn }
        for constraint in formRowConstraints { constraint.constant = metrics.formRow }
        folderTable.rowHeight = metrics.folderRow
        folderBarHeight?.constant = metrics.folderBar
        searchFieldWidth?.constant = metrics.searchWidth
        itemsBoxHeight?.constant = metrics.itemsMinHeight
        itemsHelper.isHidden = !metrics.showsItemsHelper
        updateFolderListHeight()
    }

    private func updateFolderListHeight() {
        let rows = max(1, min(settings.scripts.folders.count, 3))
        folderListHeight?.constant = folderTable.rowHeight * CGFloat(rows)
    }

    private func layoutColumns() {
        window?.contentView?.layoutSubtreeIfNeeded()
        let columns = Dictionary(uniqueKeysWithValues: itemTable.tableColumns.map { ($0.identifier, $0) })
        guard let name = columns[Column.name], let aliases = columns[Column.aliases] else { return }
        let spacing = itemTable.intercellSpacing.width * 4
        let available = max(160, itemScroll.contentSize.width - 30 - 68 - spacing)
        name.width = available * 2 / 3.6
        aliases.width = available * 1.6 / 3.6
    }

    private func recomputeFolderCounts() {
        let roots = settings.scriptFolders.map { $0.path.hasSuffix("/") ? $0.path : $0.path + "/" }
        var counts = [Int](repeating: 0, count: roots.count)
        for item in allItems {
            guard case .script(let script) = item else { continue }
            let path = script.url.path
            for (index, root) in roots.enumerated() where path.hasPrefix(root) { counts[index] += 1 }
        }
        folderCounts = counts
    }

    private func reloadFolders() {
        recomputeFolderCounts()
        folderTable.reloadData()
        watchSwitch.state = settings.scripts.watch ? .on : .off
        removeFolderButton.isEnabled = folderTable.selectedRow >= 0
        folderEmptyLabel.isHidden = !settings.scripts.folders.isEmpty
        updateFolderListHeight()
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
        folderTable.deselectAll(nil)
        reloadFolders()
        commit()
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.toggle()
        } catch {
            loginStatus.stringValue = error.localizedDescription
            loginStatus.textColor = .systemRed
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated { self.refreshLogin() }
        }
        refreshLogin()
    }

    @objc private func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func toggleWatch() {
        settings.scripts.watch = watchSwitch.state == .on
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
        if let column = itemTable.tableColumns.firstIndex(where: { $0.identifier == Column.name }) {
            itemTable.reloadData(forRowIndexes: [row], columnIndexes: [column])
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window else { return }
        let wantsCompact = window.frame.width < 600
        if wantsCompact != isCompact {
            isCompact = wantsCompact
            apply(wantsCompact ? Metrics.compact : Metrics.regular)
        }
        layoutColumns()
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === filterField { applyFilter() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === folderTable ? settings.scripts.folders.count : visibleItems.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if notification.object as? NSTableView === folderTable {
            removeFolderButton.isEnabled = folderTable.selectedRow >= 0
            return
        }
        guard notification.object as? NSTableView === itemTable else { return }
        let previous = selectedItemRow
        selectedItemRow = itemTable.selectedRow
        if previous >= 0 { refreshAliasCell(row: previous) }
        if selectedItemRow >= 0 { refreshAliasCell(row: selectedItemRow) }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        if tableView === folderTable { return FolderRowView() }
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
        if tableView === folderTable {
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? FolderCellView) ?? FolderCellView(identifier: id)
            cell.path.stringValue = settings.scripts.folders[row]
            let count = row < folderCounts.count ? folderCounts[row] : 0
            cell.count.stringValue = count == 1 ? "1 script" : "\(count) scripts"
            return cell
        }
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
            cell.imageView?.image = icons.icon(for: item, size: 16)
            cell.imageView?.alphaValue = enabled ? 1 : 0.45
            cell.textField?.font = .systemFont(ofSize: 13)
            cell.textField?.stringValue = item.title
            cell.textField?.textColor = enabled ? .labelColor : .secondaryLabelColor
            return cell
        case Column.kind:
            let cell = textCell(tableView, id: id)
            cell.textField?.font = .systemFont(ofSize: 12)
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
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
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

@MainActor
private final class FolderTable: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
private final class FolderRowView: NSTableRowView {
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
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 6, yRadius: 6).fill()
    }

    private func applySelection() {
        for case let cell as FolderCellView in subviews { cell.isRowSelected = isSelected }
    }
}

@MainActor
private final class FolderCellView: NSTableCellView {
    let symbol = NSImageView()
    let path = NSTextField(labelWithString: "")
    let count = NSTextField(labelWithString: "")

    var isRowSelected = false {
        didSet { applyStyle() }
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        symbol.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        symbol.translatesAutoresizingMaskIntoConstraints = false
        path.font = .systemFont(ofSize: 13)
        path.lineBreakMode = .byTruncatingMiddle
        path.translatesAutoresizingMaskIntoConstraints = false
        count.font = .systemFont(ofSize: 11)
        count.alignment = .right
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbol)
        addSubview(path)
        addSubview(count)
        textField = path
        imageView = symbol
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 18),
            path.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 8),
            path.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.leadingAnchor.constraint(greaterThanOrEqualTo: path.trailingAnchor, constant: 8),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyStyle()
    }

    required init?(coder: NSCoder) { nil }

    private func applyStyle() {
        let ink = SelectionPalette.ink(effectiveAppearance)
        path.textColor = isRowSelected ? ink.primary : .labelColor
        count.textColor = isRowSelected ? ink.tertiary : .tertiaryLabelColor
        symbol.contentTintColor = isRowSelected ? ink.primary : .systemTeal
    }
}

@MainActor
private final class FolderBar: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 0.5, width: bounds.width, height: 0.5).fill()
    }
}
