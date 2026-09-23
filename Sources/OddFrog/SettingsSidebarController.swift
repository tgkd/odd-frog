import AppKit

@MainActor
final class SettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((SettingsPane) -> Void)?

    private let table = NSTableView()
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

    init() {
        super.init(nibName: nil, bundle: nil)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowSizeStyle = .default
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.documentView = table
        view = scroll
    }

    func focus() {
        table.window?.makeFirstResponder(table)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        SettingsPane.allCases.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressesCallback, let pane = SettingsPane(rawValue: table.selectedRow) else { return }
        onSelect?(pane)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let pane = SettingsPane(rawValue: row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("pane")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let image = NSImageView()
            let text = NSTextField(labelWithString: "")
            cell.addSubview(image)
            cell.addSubview(text)
            cell.imageView = image
            cell.textField = text
            return cell
        }()
        cell.imageView?.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
        cell.textField?.stringValue = pane.title
        return cell
    }
}
