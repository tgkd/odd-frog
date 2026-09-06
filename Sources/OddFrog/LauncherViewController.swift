import AppKit
import OddFrogCore

@MainActor
final class LauncherViewController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let fieldHeight: CGFloat = 44
    static let fieldPadding: CGFloat = 16
    static let cornerRadius: CGFloat = 18
    static let hairlineHeight: CGFloat = 0.5
    static let hairlineInset: CGFloat = 12
    static let listInsetTop: CGFloat = 6
    static let listInsetSide: CGFloat = 8
    static let listInsetBottom: CGFloat = 8
    static let emptyStateHeight: CGFloat = 56
    static let visibleRowCap = 8

    let searchField = SearchField()
    let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let hairline = HairlineView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var scrollHeight: NSLayoutConstraint!
    private var showsEmptyState = false

    var items: [LauncherItem] = [] {
        didSet {
            subtitles = LauncherItem.subtitles(for: items)
            refresh(keepSelection: true)
        }
    }
    private var subtitles: [String: String] = [:]
    var weights: [String: Double] = [:] { didSet { refresh(keepSelection: true) } }
    var maxResults = 8 { didSet { refresh(keepSelection: true) } }
    var searchTemplate: String? { didSet { refresh(keepSelection: true) } }
    private(set) var results: [RankedItem] = []

    let icons: IconCache
    var onSubmit: ((LauncherItem, String?, Bool) -> Void)?
    var onDismiss: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onReveal: ((LauncherItem) -> Void)?
    var onSettings: (() -> Void)?

    init(icons: IconCache) {
        self.icons = icons
        super.init(nibName: nil, bundle: nil)
        icons.observeLoads { [weak self] _ in self?.tableView.reloadData(forRowIndexes: IndexSet(0..<(self?.results.count ?? 0)), columnIndexes: IndexSet(integer: 0)) }
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let content = NSView()

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(searchField)

        hairline.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hairline)

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.lineBreakMode = .byTruncatingTail
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(emptyLabel)

        let column = NSTableColumn(identifier: ResultRowView.identifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = ResultRowView.singleLineHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        tableView.refusesFirstResponder = true

        scrollView.documentView = tableView
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        scrollHeight = scrollView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            header.topAnchor.constraint(equalTo: content.topAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.fieldHeight),
            searchField.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Self.fieldPadding),
            searchField.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -Self.fieldPadding),
            searchField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            hairline.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.hairlineInset),
            hairline.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.hairlineInset),
            hairline.topAnchor.constraint(equalTo: header.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: Self.hairlineHeight),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.listInsetSide),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.listInsetSide),
            scrollView.topAnchor.constraint(equalTo: hairline.bottomAnchor, constant: Self.listInsetTop),
            scrollHeight,
            emptyLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.listInsetSide),
            emptyLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.listInsetSide),
            emptyLabel.centerYAnchor.constraint(equalTo: hairline.bottomAnchor, constant: Self.emptyStateHeight / 2),
        ])

        let root: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = content
            root = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = Self.cornerRadius
            blur.layer?.masksToBounds = true
            blur.addSubview(content)
            root = blur
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
    }

    var preferredHeight: CGFloat {
        if showsEmptyState { return Self.fieldHeight + Self.hairlineHeight + Self.emptyStateHeight }
        if results.isEmpty { return Self.fieldHeight }
        return Self.fieldHeight + Self.hairlineHeight + Self.listInsetTop + scrollHeight.constant + Self.listInsetBottom
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
        results = SearchEngine.search(query: query, items: items, weights: weights, maxResults: maxResults, searchTemplate: searchTemplate)
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
        let rows = results.count
        let visible = min(rows, Self.visibleRowCap)
        scrollHeight.constant = rows == 0 ? 0 : tableView.rect(ofRow: visible - 1).maxY
        showsEmptyState = rows == 0 && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        emptyLabel.stringValue = showsEmptyState ? "No results for “\(query)”" : ""
        emptyLabel.isHidden = !showsEmptyState
        scrollView.isHidden = showsEmptyState
        hairline.isHidden = rows == 0 && !showsEmptyState
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
        if case .script(let script) = result.item, let spec = script.argument, !spec.optional, result.argument == nil {
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
        if case .quick = item { return true }
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
        let result = results[row]
        let item = result.item
        let line = detail(for: result)
        cell.configure(title: item.title, detail: line?.detail, value: line?.value, tooltip: line?.tooltip, kind: item.kindLabel, chip: line?.chip, icon: icons.icon(for: item, size: 24))
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        (tableView.makeView(withIdentifier: ResultRow.identifier, owner: nil) as? ResultRow) ?? {
            let view = ResultRow()
            view.identifier = ResultRow.identifier
            return view
        }()
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        detail(for: results[row]) == nil ? ResultRowView.singleLineHeight : ResultRowView.twoLineHeight
    }

    private struct DetailLine {
        var detail: String
        var value: String?
        var tooltip: String?
        var chip: ResultRowView.Chip?
    }

    private static let shortPlaceholderLimit = 24

    private func detail(for result: RankedItem) -> DetailLine? {
        if case .quick(let quick) = result.item {
            return quick.subtitle.map { DetailLine(detail: $0) }
        }
        if case .script(let script) = result.item, let spec = script.argument {
            let generic = spec.placeholder.lowercased() == "argument"
            if let value = result.argument {
                let short = !generic && spec.placeholder.count <= Self.shortPlaceholderLimit
                return DetailLine(detail: (short ? spec.placeholder : "Argument") + ":", value: value, tooltip: short ? nil : spec.placeholder)
            }
            let short = !generic && spec.placeholder.count <= Self.shortPlaceholderLimit
            return DetailLine(detail: short ? spec.placeholder : "Argument", value: nil, tooltip: short ? nil : spec.placeholder, chip: spec.optional ? .optional : .required)
        }
        if case .command = result.item, let argument = result.argument {
            return DetailLine(detail: "Query:", value: argument, tooltip: nil)
        }
        guard let plain = subtitles[result.item.id] else { return nil }
        return DetailLine(detail: plain, value: nil, tooltip: nil)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    @MainActor
    private final class HairlineView: NSView {
        override var wantsUpdateLayer: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) { nil }

        override func updateLayer() {
            layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }
}
