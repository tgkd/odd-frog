import AppKit
import OddFrogCore

@MainActor
final class LauncherViewController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let cornerRadius: CGFloat = 18
    static let visibleRowCap = 8

    let searchField = SearchField()
    let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private let separator = NSBox()
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

    let icons: IconCache
    var onSubmit: ((LauncherItem, String?, Bool) -> Void)?
    var onDismiss: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onReveal: ((LauncherItem) -> Void)?
    var onSettings: (() -> Void)?
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
        searchField.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
            searchField.topAnchor.constraint(equalTo: header.layoutMarginsGuide.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: header.layoutMarginsGuide.bottomAnchor),
        ])

        separator.boxType = .separator

        emptyLabel.textColor = .secondaryLabelColor
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
        view = glass
    }

    var preferredHeight: CGFloat {
        contentStack.fittingSize.height
    }

    func clearTransientResults() {
        results.removeAll { if case .plugin(let result) = $0.item { !result.catalog } else { false } }
        if isViewLoaded { tableView.reloadData() }
    }

    func prepareForShow() {
        searchField.stringValue = ""
        refresh()
    }

    @discardableResult
    func focusField() -> Bool {
        guard let window = view.window else { return false }
        let ok = window.makeFirstResponder(searchField)
        if !ok {
            Log.write("makeFirstResponder(searchField) refused, retrying")
            return window.makeFirstResponder(searchField)
        }
        searchField.currentEditor()?.selectAll(nil)
        return ok
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
    }

    func refresh(keepSelection: Bool = false) {
        guard isViewLoaded else { return }
        let selectedID = keepSelection ? selectedItem?.id : nil
        let query = searchField.stringValue
        results = pluginQuery?(query, items, weights, maxResults)
            ?? SearchEngine.search(query: query, items: items, weights: weights, maxResults: maxResults)
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
        let rows = results.count
        let visible = min(rows, Self.visibleRowCap)
        scrollHeight.constant = rows == 0 ? 0 : tableView.rect(ofRow: visible - 1).maxY + tableView.rect(ofRow: 0).minY
        let showsEmptyState = rows == 0 && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        emptyLabel.stringValue = showsEmptyState ? "No results for “\(query)”" : ""
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

    private func fill(with item: LauncherItem) {
        searchField.stringValue = completion(for: item)
        let length = (searchField.stringValue as NSString).length
        searchField.currentEditor()?.selectedRange = NSRange(location: length, length: 0)
        refresh(keepSelection: true)
    }

    private func submit(secondary: Bool = false) {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        let result = results[row]
        if case .plugin(let live) = result.item, live.item.primary == nil { return }
        if case .plugin(let plugin) = result.item, let spec = plugin.item.argument, !spec.optional, result.argument == nil {
            fill(with: result.item)
            return
        }
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
        return false
    }

    private func isQuick(_ item: LauncherItem) -> Bool {
        if case .plugin(let result) = item { return !result.catalog }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            select(row: tableView.selectedRow + 1)
        case #selector(NSResponder.moveUp(_:)):
            select(row: tableView.selectedRow - 1)
        case #selector(NSResponder.insertNewline(_:)):
            submit()
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss?()
        case #selector(NSResponder.moveToBeginningOfDocument(_:)):
            select(row: 0)
        case #selector(NSResponder.moveToEndOfDocument(_:)):
            select(row: results.count - 1)
        case #selector(NSResponder.insertTab(_:)):
            if let item = selectedItem { fill(with: item) }
        case #selector(NSResponder.insertBacktab(_:)):
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
