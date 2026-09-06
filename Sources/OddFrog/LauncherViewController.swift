import AppKit
import OddFrogCore

@MainActor
final class LauncherViewController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let fieldHeight: CGFloat = 44
    static let listPadding: CGFloat = 6

    let searchField = SearchField()
    let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let separator = NSBox()
    private var scrollHeight: NSLayoutConstraint!

    var items: [LauncherItem] = [] {
        didSet {
            subtitles = LauncherItem.subtitles(for: items)
            refresh()
        }
    }
    private var subtitles: [String: String] = [:]
    var weights: [String: Double] = [:] { didSet { refresh() } }
    var maxResults = 8 { didSet { refresh() } }
    private(set) var results: [RankedItem] = []

    let icons: IconCache
    var onSubmit: ((LauncherItem, String?) -> Void)?
    var onDismiss: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    init(icons: IconCache) {
        self.icons = icons
        super.init(nibName: nil, bundle: nil)
        icons.onLoaded = { [weak self] _ in self?.tableView.reloadData(forRowIndexes: IndexSet(0..<(self?.results.count ?? 0)), columnIndexes: IndexSet(integer: 0)) }
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(searchField)

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(separator)

        let column = NSTableColumn(identifier: ResultRowView.identifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = ResultRowView.singleLineHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        tableView.refusesFirstResponder = true

        scrollView.documentView = tableView
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        scrollHeight = scrollView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.fieldHeight),
            searchField.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            searchField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: Self.listPadding / 2),
            scrollHeight,
        ])
        view = root
    }

    var preferredHeight: CGFloat {
        if results.isEmpty { return Self.fieldHeight }
        return Self.fieldHeight + 1 + Self.listPadding / 2 + scrollHeight.constant
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

    func refresh() {
        guard isViewLoaded else { return }
        let selectedID = selectedItem?.id
        results = SearchEngine.search(query: searchField.stringValue, items: items, weights: weights, maxResults: maxResults)
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
        let rows = results.count
        let visible = min(rows, maxResults)
        scrollHeight.constant = visible == 0 ? 0 : tableView.rect(ofRow: visible - 1).maxY + Self.listPadding / 2
        separator.isHidden = rows == 0
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

    private func submit() {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        onSubmit?(results[row].item, results[row].argument)
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        select(row: row)
        submit()
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
        cell.configure(title: item.title, detail: line?.detail, value: line?.value, tooltip: line?.tooltip, kind: item.kindLabel, icon: icons.icon(for: item))
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        detail(for: results[row]) == nil ? ResultRowView.singleLineHeight : ResultRowView.twoLineHeight
    }

    private struct DetailLine {
        var detail: String
        var value: String?
        var tooltip: String?
    }

    private static let shortPlaceholderLimit = 24

    private func detail(for result: RankedItem) -> DetailLine? {
        if case .script(let script) = result.item, let spec = script.argument {
            let generic = spec.placeholder.lowercased() == "argument"
            if let value = result.argument {
                let short = !generic && spec.placeholder.count <= Self.shortPlaceholderLimit
                return DetailLine(detail: (short ? spec.placeholder : "Argument") + ":", value: value, tooltip: short ? nil : spec.placeholder)
            }
            let label = generic ? "Argument" : spec.placeholder
            return DetailLine(detail: "\(label): \(spec.optional ? "optional" : "required")", value: nil, tooltip: nil)
        }
        guard let plain = subtitles[result.item.id] else { return nil }
        return DetailLine(detail: plain, value: nil, tooltip: nil)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}
