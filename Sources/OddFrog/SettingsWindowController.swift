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

    let pluginsPane = PluginsPane()
    private let linkManager = LinkManagerController()
    var onApplyLink: ((CommandItem?, LinkDraft?) throws -> [CommandItem])?

    private let icons: IconCache
    private let folderTable = FolderTable()
    private let folderScroll = NSScrollView()
    private let itemTable = ItemTable()
    private let itemScroll = NSScrollView()
    private let filterField = NSSearchField()
    private let hotkeyRecorder = HotkeyRecorder()
    private let hotkeyHelper = NSTextField(labelWithString: "")
    private let webSearchField = NSTextField()
    private let webSearchHelper = NSTextField(labelWithString: "")
    private let currencySwitch = NSSwitch()
    private let currencyHelper = NSTextField(labelWithString: "")
    private let windowSwitch = NSSwitch()
    private let windowAccessButton = NSButton(title: "Open System Settings", target: nil, action: nil)
    private let windowHelper = NSTextField(wrappingLabelWithString: "")
    private let loginSwitch = NSSwitch()
    private let loginStatus = NSTextField(labelWithString: "")
    private let loginButton = NSButton(title: "Open Login Items…", target: nil, action: nil)
    private let addFolderButton = NSButton(title: "+", target: nil, action: nil)
    private let removeFolderButton = NSButton(title: "−", target: nil, action: nil)
    private let watchSwitch = NSSwitch()
    private let folderEmptyLabel = NSTextField(labelWithString: "No script folders yet. Click + to add one.")
    private let itemsHelper = NSTextField(labelWithString: "Grey aliases are built in. Click a cell to add your own; Return saves.")
    private let itemsEmptyLabel = NSTextField(labelWithString: "")
    private let sidebar = SettingsSidebar()
    private let paneTitle = NSTextField(labelWithString: "")
    private let accessLine = NSView()

    private var panes: [SettingsPane: NSView] = [:]
    private var currentPane = SettingsPane.general
    private var folderListHeight: NSLayoutConstraint?
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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Odd Frog Settings"
        window.minSize = NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        let toolbar = NSToolbar(identifier: "settings")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.center()
        super.init(window: window)
        buildContent()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        icons.observeLoads { [weak self] path in
            guard let self, window.isVisible else { return }
            let rows = visibleItems.indices.filter { row in
                guard case .app(let app) = visibleItems[row] else { return false }
                return app.url.path == path
            }
            let column = itemTable.column(withIdentifier: Column.name)
            guard !rows.isEmpty, column >= 0 else { return }
            itemTable.reloadData(forRowIndexes: IndexSet(rows), columnIndexes: IndexSet(integer: column))
        }
    }

    required init?(coder: NSCoder) { nil }

    func present(settings: Settings, items: [LauncherItem], hotkey: Hotkey) {
        present(settings: settings, items: items, hotkey: hotkey, focusing: nil)
    }

    func present(settings: Settings, items: [LauncherItem], hotkey: Hotkey, focusing id: String?) {
        self.settings = settings
        self.allItems = items
        showHotkey(hotkey)
        refreshLogin()
        reloadFolders()
        let target = id.flatMap { targetID in items.first { $0.id == targetID } }
        filterField.stringValue = target?.title ?? ""
        applyFilter()
        webSearchField.stringValue = settings.search.url
        refreshWindowManagement()
        resetWebSearchHelper()
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
            window?.makeFirstResponder(currentPane == .items ? filterField : nil)
            layoutColumns()
        }
    }

    private func showPane(_ pane: SettingsPane) {
        if currentPane == .items, pane != .items { endAliasEdit(commit: true) }
        currentPane = pane
        sidebar.selected = pane
        paneTitle.stringValue = pane.title
        for (key, view) in panes { view.isHidden = key != pane }
        guard pane == .items else { return }
        layoutColumns()
        window?.makeFirstResponder(filterField)
    }

    func update(items: [LauncherItem]) {
        allItems = items
        recomputeFolderCounts()
        folderTable.reloadData()
        applyFilter()
    }

    func update(pluginSettings: [PluginSetting]) { settings.plugins = pluginSettings }

    func update(windowSettings: Settings.Window) {
        settings.window = windowSettings
        if window?.isVisible == true { refreshWindowManagement() }
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
        sidebar.onSelect = { [weak self] pane in self?.showPane(pane) }

        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        paneTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        paneTitle.isSelectable = false
        paneTitle.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(sidebar)
        content.addSubview(host)
        host.addSubview(paneTitle)
        host.addSubview(container)

        panes = [
            .general: makeGeneralPane(),
            .folders: makeFoldersPane(),
            .items: makeItemsPane(),
            .plugins: pluginsPane,
        ]
        for (pane, view) in panes {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
            if pane == .items || pane == .plugins {
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
            } else {
                view.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor).isActive = true
            }
        }

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 200),
            host.topAnchor.constraint(equalTo: content.topAnchor),
            host.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            paneTitle.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
            paneTitle.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -20),
            paneTitle.centerYAnchor.constraint(equalTo: host.topAnchor, constant: 26),
            container.topAnchor.constraint(equalTo: host.topAnchor, constant: 52),
            container.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -20),
        ])

        showPane(.general)
    }

    private func makeGeneralPane() -> NSView {
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

        loginSwitch.controlSize = .small
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin)
        style(helper: loginStatus)
        loginButton.target = self
        loginButton.action = #selector(openLoginItems)
        loginButton.bezelStyle = .rounded
        loginButton.controlSize = .small
        loginButton.font = .systemFont(ofSize: 11)
        loginButton.isHidden = true
        let loginControl = NSStackView(views: [loginSwitch, loginButton])
        loginControl.orientation = .horizontal
        loginControl.spacing = 8
        loginControl.alignment = .centerY

        windowSwitch.controlSize = .small
        windowSwitch.target = self
        windowSwitch.action = #selector(toggleWindowManagement)
        style(helper: windowHelper)
        windowHelper.stringValue = "Move and resize the front window from the launcher."

        currencySwitch.controlSize = .small
        currencySwitch.target = self
        currencySwitch.action = #selector(toggleCurrency)
        style(helper: currencyHelper)
        currencyHelper.stringValue = "Rates from exchangerate-api.com."

        webSearchField.bezelStyle = .roundedBezel
        webSearchField.usesSingleLineMode = true
        webSearchField.lineBreakMode = .byTruncatingTail
        webSearchField.placeholderString = Settings.Search.defaultURL
        webSearchField.font = .systemFont(ofSize: 13)
        webSearchField.delegate = self
        webSearchField.translatesAutoresizingMaskIntoConstraints = false
        webSearchField.widthAnchor.constraint(equalToConstant: 290).isActive = true
        style(helper: webSearchHelper)
        resetWebSearchHelper()

        buildAccessLine()

        let shortcuts = groupedBox([
            settingRow(title: "Keyboard shortcut", subtitle: hotkeyHelper, control: hotkeyRecorder),
            hairline(),
            settingRow(title: "Launch at login", subtitle: loginStatus, control: loginControl),
        ])
        let search = groupedBox([
            settingRow(title: "Web search", subtitle: webSearchHelper, control: webSearchField),
        ])
        let extras = groupedBox([
            settingRow(title: "Window management", subtitle: windowHelper, control: windowSwitch),
            accessLine,
            hairline(),
            settingRow(title: "Currency conversion", subtitle: currencyHelper, control: currencySwitch),
        ])

        return stackedPane([
            shortcuts,
            sectionHeader("Search"),
            search,
            sectionHeader("Extras"),
            extras,
        ])
    }

    private func buildAccessLine() {
        accessLine.translatesAutoresizingMaskIntoConstraints = false
        accessLine.isHidden = true
        let label = NSTextField(wrappingLabelWithString: "Allow Odd Frog under Privacy & Security › Accessibility.")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemRed
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        windowAccessButton.title = "Open System Settings…"
        windowAccessButton.target = self
        windowAccessButton.action = #selector(openAccessibilitySettings)
        windowAccessButton.bezelStyle = .rounded
        windowAccessButton.controlSize = .small
        windowAccessButton.font = .systemFont(ofSize: 11)
        windowAccessButton.translatesAutoresizingMaskIntoConstraints = false
        windowAccessButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        accessLine.addSubview(label)
        accessLine.addSubview(windowAccessButton)
        let collapse = accessLine.heightAnchor.constraint(equalToConstant: 32)
        collapse.priority = NSLayoutConstraint.Priority(250)
        NSLayoutConstraint.activate([
            accessLine.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            collapse,
            label.leadingAnchor.constraint(equalTo: accessLine.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: windowAccessButton.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: windowAccessButton.leadingAnchor, constant: -16),
            windowAccessButton.trailingAnchor.constraint(equalTo: accessLine.trailingAnchor, constant: -16),
            windowAccessButton.topAnchor.constraint(greaterThanOrEqualTo: accessLine.topAnchor),
            windowAccessButton.bottomAnchor.constraint(equalTo: accessLine.bottomAnchor, constant: -10),
        ])
    }

    private func makeFoldersPane() -> NSView {
        let column = NSTableColumn(identifier: Column.folder)
        column.resizingMask = .autoresizingMask
        folderTable.addTableColumn(column)
        folderTable.headerView = nil
        folderTable.dataSource = self
        folderTable.delegate = self
        folderTable.rowHeight = 44
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

        addFolderButton.target = self
        addFolderButton.action = #selector(addFolder)
        removeFolderButton.target = self
        removeFolderButton.action = #selector(removeFolder)
        removeFolderButton.isEnabled = false
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        for button in [addFolderButton, removeFolderButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(button)
            button.widthAnchor.constraint(equalToConstant: 26).isActive = true
            button.centerYAnchor.constraint(equalTo: bar.centerYAnchor).isActive = true
        }

        watchSwitch.controlSize = .small
        watchSwitch.target = self
        watchSwitch.action = #selector(toggleWatch)
        let watchHelper = NSTextField(labelWithString: "Rescan when a script is added, removed or edited.")
        style(helper: watchHelper)

        let listBox = GroupBox()
        listBox.translatesAutoresizingMaskIntoConstraints = false
        let line = hairline()
        listBox.addSubview(folderScroll)
        listBox.addSubview(folderEmptyLabel)
        listBox.addSubview(line)
        listBox.addSubview(bar)

        let listHeight = folderScroll.heightAnchor.constraint(equalToConstant: 44)
        folderListHeight = listHeight

        NSLayoutConstraint.activate([
            folderScroll.topAnchor.constraint(equalTo: listBox.topAnchor),
            folderScroll.leadingAnchor.constraint(equalTo: listBox.leadingAnchor),
            folderScroll.trailingAnchor.constraint(equalTo: listBox.trailingAnchor),
            listHeight,
            folderEmptyLabel.centerXAnchor.constraint(equalTo: folderScroll.centerXAnchor),
            folderEmptyLabel.centerYAnchor.constraint(equalTo: folderScroll.centerYAnchor),
            line.topAnchor.constraint(equalTo: folderScroll.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: listBox.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: listBox.trailingAnchor),
            bar.topAnchor.constraint(equalTo: line.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: listBox.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: listBox.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: listBox.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 40),
            addFolderButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            removeFolderButton.leadingAnchor.constraint(equalTo: addFolderButton.trailingAnchor, constant: 6),
        ])

        return stackedPane([
            makeFoldersIntro(),
            sectionHeader("Folders"),
            listBox,
            groupedBox([settingRow(title: "Watch for changes", subtitle: watchHelper, control: watchSwitch)]),
        ])
    }

    private func makeFoldersIntro() -> NSView {
        let box = GroupBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        let tile = IconTile(color: .systemTeal, symbol: "folder.fill", side: 28, radius: 7, pointSize: 15)
        let title = NSTextField(labelWithString: "Script Folders")
        title.font = .systemFont(ofSize: 13)
        title.isSelectable = false
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        let summary = NSTextField(wrappingLabelWithString: "Executable scripts in these folders appear in the launcher. Raycast script metadata is optional.")
        style(helper: summary)
        summary.lineBreakMode = .byWordWrapping
        summary.maximumNumberOfLines = 0
        summary.cell?.wraps = true
        summary.cell?.isScrollable = false
        box.addSubview(tile)
        box.addSubview(title)
        box.addSubview(summary)
        NSLayoutConstraint.activate([
            tile.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            tile.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -16),
            summary.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            summary.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            summary.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            summary.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
        ])
        return box
    }

    private func makeItemsPane() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        style(helper: itemsHelper)
        itemsHelper.lineBreakMode = .byTruncatingTail
        itemsHelper.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        itemsHelper.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        filterField.placeholderString = "Filter"
        filterField.controlSize = .regular
        filterField.font = .systemFont(ofSize: 13)
        filterField.delegate = self
        filterField.translatesAutoresizingMaskIntoConstraints = false

        let manageLinks = NSButton(title: "Manage Links…", target: self, action: #selector(showLinks))
        manageLinks.bezelStyle = .rounded
        manageLinks.controlSize = .regular
        manageLinks.font = .systemFont(ofSize: 13)
        manageLinks.setContentCompressionResistancePriority(.required, for: .horizontal)
        manageLinks.setContentHuggingPriority(.required, for: .horizontal)
        let footer = NSStackView(views: [itemsHelper, manageLinks])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false

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

        style(helper: itemsEmptyLabel)
        itemsEmptyLabel.font = .systemFont(ofSize: 13)
        itemsEmptyLabel.alignment = .center
        itemsEmptyLabel.isHidden = true

        let box = GroupBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(itemScroll)
        box.addSubview(itemsEmptyLabel)
        container.addSubview(filterField)
        container.addSubview(box)
        container.addSubview(footer)

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
            footer.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 12),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            itemScroll.topAnchor.constraint(equalTo: box.topAnchor),
            itemScroll.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            itemScroll.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
            itemScroll.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            itemsEmptyLabel.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            itemsEmptyLabel.centerYAnchor.constraint(equalTo: box.centerYAnchor, constant: -12),
        ])
        return container
    }

    private func settingRow(title: String, subtitle: NSTextField, control: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let caption = NSTextField(labelWithString: title)
        caption.font = .systemFont(ofSize: 13)
        caption.isSelectable = false
        caption.lineBreakMode = .byTruncatingTail
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 0
        subtitle.cell?.wraps = true
        subtitle.cell?.isScrollable = false
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        let text = NSView()
        text.translatesAutoresizingMaskIntoConstraints = false
        text.addSubview(caption)
        text.addSubview(subtitle)
        row.addSubview(text)
        row.addSubview(control)
        let collapse = row.heightAnchor.constraint(equalToConstant: 44)
        collapse.priority = NSLayoutConstraint.Priority(250)

        NSLayoutConstraint.activate([
            caption.topAnchor.constraint(equalTo: text.topAnchor),
            caption.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            caption.trailingAnchor.constraint(lessThanOrEqualTo: text.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: text.trailingAnchor),
            subtitle.bottomAnchor.constraint(equalTo: text.bottomAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            collapse,
            text.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            text.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            text.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: text.trailingAnchor, constant: 16),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func groupedBox(_ rows: [NSView]) -> NSView {
        let box = GroupBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        for row in rows { row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return box
    }

    private func hairline() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let line = Hairline()
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 0.5),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            line.topAnchor.constraint(equalTo: container.topAnchor),
            line.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func sectionHeader(_ text: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let label = groupTitle(text)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func stackedPane(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
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

    private func updateFolderListHeight() {
        let rows = max(1, min(settings.scripts.folders.count, 5))
        folderListHeight?.constant = folderTable.rowHeight * CGFloat(rows)
    }

    private func layoutColumns() {
        window?.contentView?.layoutSubtreeIfNeeded()
        let columns = Dictionary(uniqueKeysWithValues: itemTable.tableColumns.map { ($0.identifier, $0) })
        guard let name = columns[Column.name], let aliases = columns[Column.aliases] else { return }
        let available = max(160, itemScroll.contentSize.width - 16 - 32 - 64)
        name.width = available * 2 / 3.4
        aliases.width = available * 1.4 / 3.4
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

    private func resetWebSearchHelper() {
        webSearchHelper.stringValue = "Used when nothing matches. {query} is replaced with your search."
        webSearchHelper.textColor = .secondaryLabelColor
    }

    @objc private func showLinks() {
        guard let window else { return }
        endAliasEdit(commit: true)
        let links = allItems.compactMap { item -> CommandItem? in
            guard case .command(let command) = item, case .url = command.action else { return nil }
            return command
        }
        linkManager.onApply = onApplyLink
        linkManager.present(links: links, for: window)
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

    private func refreshWindowManagement() {
        currencySwitch.state = settings.currency.enabled ? .on : .off
        windowSwitch.state = settings.window.enabled ? .on : .off
        accessLine.isHidden = !(settings.window.enabled && !WindowManager.hasAccess)
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        refreshWindowManagement()
    }

    @objc private func toggleCurrency() {
        settings.currency.enabled = currencySwitch.state == .on
        commit()
    }

    @objc private func toggleWindowManagement() {
        settings.window.enabled = windowSwitch.state == .on
        commit()
        if settings.window.enabled && !WindowManager.hasAccess {
            WindowManager.requestAccess()
        }
        refreshWindowManagement()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated { self.refreshWindowManagement() }
        }
    }

    @objc private func openAccessibilitySettings() {
        WindowManager.openAccessibilitySettings()
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
        layoutColumns()
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === filterField { applyFilter() }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === webSearchField else { return }
        let trimmed = webSearchField.stringValue.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(URLTemplate.placeholder), URLTemplate.resolve(template: trimmed, query: "test") != nil {
            settings.search.url = trimmed
            commit()
            resetWebSearchHelper()
        } else {
            webSearchHelper.stringValue = "Enter a full URL containing {query}."
            webSearchHelper.textColor = .systemRed
            webSearchField.stringValue = settings.search.url
        }
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
        bounds.fill()
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
        count.font = .systemFont(ofSize: 13)
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
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 18),
            path.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 12),
            path.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.leadingAnchor.constraint(greaterThanOrEqualTo: path.trailingAnchor, constant: 8),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }
}
