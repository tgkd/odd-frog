import AppKit
import OddFrogCore

@MainActor
final class LauncherViewController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let cornerRadius: CGFloat = 18
    static let queryInset: CGFloat = 10
    static let visibleRowCap = 8

    let searchField = SearchField()
    let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private let separator = NSBox()
    private let chip = TriggerChip()
    private let emptyBand = NSView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let prototype = ResultRowView()
    private var scrollHeight: NSLayoutConstraint!

    var items: [LauncherItem] = [] {
        didSet {
            guard items != oldValue else { return }
            subtitles = LauncherItem.subtitles(for: items)
            refresh(keepSelection: true)
        }
    }
    private var subtitles: [String: String] = [:]
    var weights: [String: Double] = [:] {
        didSet {
            guard weights != oldValue else { return }
            refresh(keepSelection: true)
        }
    }
    var maxResults = 8 { didSet { refresh(keepSelection: true) } }
    private(set) var results: [RankedItem] = []
    /// Plugins the field can enter; set by the host whenever plugins or their triggers change.
    var pluginEntries: [(package: PluginPackage, trigger: PluginTrigger)] = []
    private(set) var activeTrigger: (package: PluginPackage, trigger: PluginTrigger)?
    var history: [String] = [] { didSet { historyIndex = nil } }
    private var historyIndex: Int?

    let icons: IconCache
    var onSubmit: ((LauncherItem, String?, Bool) -> Void)?
    var onDismiss: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onReveal: ((LauncherItem) -> Void)?
    var onSettings: (() -> Void)?
    var onEnterPlugin: ((LauncherItem) -> Void)?
    var onRecordQuery: ((String) -> Void)?
    var pluginQuery: ((String, [LauncherItem], [String: Double], Int) -> [RankedItem])?

    init(icons: IconCache) {
        self.icons = icons
        super.init(nibName: nil, bundle: nil)
        icons.observeLoads { [weak self] path in
            guard let self else { return }
            let rows = results.indices.filter { row in
                return results[row].item.result.item.icon == path
            }
            guard !rows.isEmpty else { return }
            tableView.reloadData(forRowIndexes: IndexSet(rows), columnIndexes: IndexSet(integer: 0))
        }
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let content = NSView()

        let header = NSView()
        searchField.delegate = self
        chip.isHidden = true
        let queryRow = NSStackView(views: [chip, searchField])
        queryRow.orientation = .horizontal
        queryRow.alignment = .centerY
        queryRow.spacing = 6
        queryRow.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(queryRow)
        NSLayoutConstraint.activate([
            queryRow.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
            queryRow.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
            queryRow.topAnchor.constraint(equalTo: header.topAnchor, constant: Self.queryInset),
            header.bottomAnchor.constraint(equalTo: queryRow.bottomAnchor, constant: Self.queryInset),
        ])

        separator.boxType = .separator

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = ContentFont.current.font(.body)
        emptyLabel.alignment = .center
        emptyLabel.lineBreakMode = .byTruncatingTail
        emptyLabel.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyBand.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.leadingAnchor.constraint(equalTo: emptyBand.layoutMarginsGuide.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: emptyBand.layoutMarginsGuide.trailingAnchor),
            emptyLabel.topAnchor.constraint(equalTo: emptyBand.layoutMarginsGuide.topAnchor),
            emptyLabel.bottomAnchor.constraint(equalTo: emptyBand.layoutMarginsGuide.bottomAnchor),
        ])

        let column = NSTableColumn(identifier: ResultRowView.identifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        tableView.refusesFirstResponder = true

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.distribution = .fill
        contentStack.spacing = 0
        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(separator)
        contentStack.addArrangedSubview(scrollView)
        contentStack.addArrangedSubview(emptyBand)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(contentStack)

        scrollHeight = scrollView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: content.topAnchor),
            scrollHeight,
        ])

        let glass = NSGlassEffectView()
        glass.cornerRadius = Self.cornerRadius
        glass.contentView = content
        glass.translatesAutoresizingMaskIntoConstraints = false

        // The glass draws its own shadow outside its rounded shape; the window is exactly the glass
        // size, so that shadow shows as a square-cornered halo unless it is clipped to the same shape.
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.cornerRadius = Self.cornerRadius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            glass.topAnchor.constraint(equalTo: clip.topAnchor),
            glass.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
        ])
        view = clip
    }

    var preferredHeight: CGFloat {
        contentStack.fittingSize.height
    }

    func clearTransientResults() {
        results.removeAll { if case .plugin(let result) = $0.item { !result.catalog } else { false } }
        if isViewLoaded { tableView.reloadData() }
    }

    func prepareForShow() {
        historyIndex = nil
        setActiveTrigger(nil)
        searchField.stringValue = ""
        refresh()
    }

    func setQuery(_ query: String) {
        historyIndex = nil
        setActiveTrigger(nil)
        setFieldText(query)
        absorbTypedTrigger()
        refresh()
    }

    private func recallHistory(at index: Int) {
        guard history.indices.contains(index) else { return }
        setQuery(history[index])
        historyIndex = index
    }

    private func moveUp() {
        if tableView.selectedRow != 0, !results.isEmpty {
            select(row: tableView.selectedRow - 1)
            return
        }
        if let index = historyIndex {
            recallHistory(at: index + 1)
        } else if fullQuery.allSatisfy(\.isWhitespace) {
            recallHistory(at: 0)
        }
    }

    /// The query the plugins see: the chip's trigger text followed by the field.
    var fullQuery: String { (activeTrigger?.trigger.launchQuery ?? "") + searchField.stringValue }

    func enterPlugin(_ entry: (package: PluginPackage, trigger: PluginTrigger), filter: String = "") {
        setActiveTrigger(entry)
        setFieldText(filter)
        refresh()
    }

    func leavePlugin() {
        guard activeTrigger != nil else { return }
        setActiveTrigger(nil)
        setFieldText("")
        refresh()
    }

    private func setActiveTrigger(_ entry: (package: PluginPackage, trigger: PluginTrigger)?) {
        activeTrigger = entry
        chip.title = entry?.package.manifest.name ?? ""
        chip.isHidden = entry == nil
        searchField.placeholderString = entry.map { "Search \($0.package.manifest.name)…" } ?? SearchField.placeholder
    }

    private func setFieldText(_ text: String) {
        searchField.stringValue = text
        let length = (text as NSString).length
        searchField.currentEditor()?.selectedRange = NSRange(location: length, length: 0)
    }

    /// Turns a trigger typed into the root field (`clip ` or `>`) into the chip, leaving only the filter in the field.
    private func absorbTypedTrigger() {
        guard activeTrigger == nil else { return }
        let text = searchField.stringValue
        for entry in pluginEntries {
            switch entry.trigger {
            case .keyword(let keyword):
                let head = text.prefix { !$0.isWhitespace }
                guard head.lowercased() == keyword, text.count > head.count else { continue }
                enterPlugin(entry, filter: String(text.dropFirst(head.count + 1)))
            case .prefix(let prefix):
                guard text.hasPrefix(prefix) else { continue }
                enterPlugin(entry, filter: String(text.dropFirst(prefix.count)))
            }
            return
        }
    }

    @discardableResult
    func focusField() -> Bool {
        guard let window = view.window else { return false }
        let ok = window.makeFirstResponder(searchField)
        if !ok {
            Log.write("makeFirstResponder(searchField) refused, retrying")
            return window.makeFirstResponder(searchField)
        }
        let length = (searchField.stringValue as NSString).length
        searchField.currentEditor()?.selectedRange = NSRange(location: length, length: 0)
        return ok
    }

    func applyContentFont() {
        searchField.font = ContentFont.current.font(.title2)
        chip.applyContentFont()
        emptyLabel.font = ContentFont.current.font(.body)
        refresh(keepSelection: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
    }

    func refresh(keepSelection: Bool = false) {
        guard isViewLoaded else { return }
        let selectedID = keepSelection ? selectedItem?.id : nil
        let query = fullQuery
        results = pluginQuery?(query, items, weights, maxResults)
            ?? SearchEngine.search(query: query, items: items, weights: weights, maxResults: maxResults)
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
        let rows = results.count
        let visible = min(rows, Self.visibleRowCap)
        scrollHeight.constant = rows == 0 ? 0 : tableView.rect(ofRow: visible - 1).maxY + tableView.rect(ofRow: 0).minY
        let filter = searchField.stringValue
        let showsEmptyState = rows == 0 && !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        emptyLabel.stringValue = showsEmptyState ? "No results for “\(filter)”" : ""
        emptyBand.isHidden = !showsEmptyState
        scrollView.isHidden = rows == 0
        separator.isHidden = rows == 0 && !showsEmptyState
        if rows > 0 {
            let row = selectedID.flatMap { id in results.firstIndex { $0.item.id == id } } ?? 0
            select(row: row)
        }
        onHeightChange?(preferredHeight)
    }

    var selectedItem: LauncherItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return nil }
        return results[row].item
    }

    private func select(row: Int) {
        guard !results.isEmpty else { return }
        let clamped = max(0, min(row, results.count - 1))
        tableView.selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
        tableView.scrollRowToVisible(clamped)
    }

    private func completion(for item: LauncherItem) -> String {
        if case .plugin(let result) = item, let completion = result.item.completion { return completion }
        let base = item.aliases.first ?? item.title
        return item.acceptsArgument ? base + " " : base
    }

    private func pluginEntry(for item: LauncherItem) -> (package: PluginPackage, trigger: PluginTrigger)? {
        guard item.result.item.id == PluginCoordinator.entryItemID else { return nil }
        return pluginEntries.first { $0.package.manifest.id == item.result.pluginID }
    }

    private func enter(_ item: LauncherItem, _ entry: (package: PluginPackage, trigger: PluginTrigger)) {
        onEnterPlugin?(item)
        enterPlugin(entry)
    }

    private func fill(with item: LauncherItem) {
        historyIndex = nil
        if let entry = pluginEntry(for: item) {
            enter(item, entry)
            return
        }
        setFieldText(completion(for: item))
        refresh(keepSelection: true)
    }

    private func submit(secondary: Bool = false) {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        let result = results[row]
        if let entry = pluginEntry(for: result.item) {
            enter(result.item, entry)
            return
        }
        if case .plugin(let live) = result.item, live.item.primary == nil { return }
        if case .plugin(let plugin) = result.item, let spec = plugin.item.argument, !spec.optional, result.argument == nil {
            fill(with: result.item)
            return
        }
        onRecordQuery?(fullQuery)
        onSubmit?(result.item, result.argument, secondary)
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        select(row: row)
        submit()
    }

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        if event.keyCode == 36 || event.keyCode == 76 {
            submit(secondary: true)
            return true
        }
        if let characters = event.charactersIgnoringModifiers, characters.count == 1,
           let digit = characters.first, let n = digit.wholeNumberValue, (1...9).contains(n) {
            if results.count >= n {
                select(row: n - 1)
                submit()
            }
            return true
        }
        if event.charactersIgnoringModifiers == "i" {
            if let item = selectedItem, !isQuick(item) {
                onReveal?(item)
            }
            return true
        }
        if event.charactersIgnoringModifiers == "," {
            onSettings?()
            return true
        }
        if event.charactersIgnoringModifiers == "q" || event.charactersIgnoringModifiers == "h" {
            return true
        }
        if let characters = event.charactersIgnoringModifiers,
           !characters.allSatisfy(\.isASCII),
           event.keyCode == 12 || event.keyCode == 4 {
            return true
        }
        return false
    }

    private func isQuick(_ item: LauncherItem) -> Bool {
        if case .plugin(let result) = item { return !result.catalog }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        historyIndex = nil
        replaceLineBreaks()
        absorbTypedTrigger()
        refresh()
    }

    private func replaceLineBreaks() {
        guard let editor = searchField.currentEditor(),
              editor.string.unicodeScalars.contains(where: CharacterSet.newlines.contains) else {
            return
        }
        let selection = editor.selectedRange
        let scalars = editor.string.unicodeScalars.map { CharacterSet.newlines.contains($0) ? " " : $0 }
        editor.string = String(String.UnicodeScalarView(scalars))
        editor.selectedRange = selection
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            select(row: tableView.selectedRow + 1)
        case #selector(NSResponder.moveUp(_:)):
            moveUp()
        case #selector(NSResponder.insertNewline(_:)):
            submit()
        case #selector(NSResponder.cancelOperation(_:)):
            if activeTrigger != nil { leavePlugin() } else { onDismiss?() }
        case #selector(NSResponder.deleteBackward(_:)):
            guard activeTrigger != nil, searchField.stringValue.isEmpty else { return false }
            leavePlugin()
        case #selector(NSResponder.moveToBeginningOfDocument(_:)):
            select(row: 0)
        case #selector(NSResponder.moveToEndOfDocument(_:)):
            select(row: results.count - 1)
        case #selector(NSResponder.insertTab(_:)):
            if let item = selectedItem { fill(with: item) }
        case #selector(NSResponder.insertBacktab(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
             #selector(NSResponder.insertLineBreak(_:)):
            break
        default:
            return false
        }
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: ResultRowView.identifier, owner: nil) as? ResultRowView) ?? ResultRowView()
        configure(cell, row: row, icon: icons.icon(for: results[row].item, size: ResultRowView.iconSide))
        return cell
    }

    private func configure(_ cell: ResultRowView, row: Int, icon: NSImage?) {
        let result = results[row]
        let item = result.item
        let line = detail(for: result)
        cell.configure(title: item.title, detail: line?.detail, value: line?.value, tooltip: line?.tooltip, kind: item.kindLabel, requirement: line?.requirement, icon: icon)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        (tableView.makeView(withIdentifier: ResultRow.identifier, owner: nil) as? ResultRow) ?? {
            let view = ResultRow()
            view.identifier = ResultRow.identifier
            return view
        }()
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        configure(prototype, row: row, icon: nil)
        return prototype.fittingSize.height
    }

    private struct DetailLine {
        var detail: String
        var value: String?
        var tooltip: String?
        var requirement: ResultRowView.Requirement?
    }

    private static let shortPlaceholderLimit = 24

    private func detail(for result: RankedItem) -> DetailLine? {
        if case .plugin(let live) = result.item {
            if let spec = live.item.argument {
                return DetailLine(detail: spec.placeholder, value: result.argument,
                                  requirement: result.argument == nil ? (spec.optional ? .optional : .required) : nil)
            }
            return live.item.subtitle.map { DetailLine(detail: $0) }
        }
        guard let plain = subtitles[result.item.id] else { return nil }
        return DetailLine(detail: plain, value: nil, tooltip: nil)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}
