import AppKit
import OddFrogPluginAPI

@MainActor
final class ChatTranscriptView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private var messages: [PluginMessage] = []
    private var replyID: String?
    private var assistant = ""
    private let stickyBottom: CGFloat = 24

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: ChatMessageCell.identifier)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .inset
        table.usesAutomaticRowHeights = true
        table.refusesFirstResponder = true
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Transcript")

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ messages: [PluginMessage], streaming replyID: String?, assistant: String) {
        let sticky = isNearBottom()
        let previous = self.messages
        let previousReplyID = self.replyID
        let same = previous.map(\.id) == messages.map(\.id) && self.assistant == assistant
        var changed = IndexSet()
        if same {
            for (index, message) in messages.enumerated() {
                if previous[index].text != message.text {
                    changed.insert(index)
                }
                if message.id == previousReplyID || message.id == replyID {
                    changed.insert(index)
                }
            }
        }

        self.messages = messages
        self.replyID = replyID
        self.assistant = assistant

        if same {
            if !changed.isEmpty {
                table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
                table.noteHeightOfRows(withIndexesChanged: changed)
            }
        } else {
            table.reloadData()
        }

        if sticky {
            scrollToBottom()
        }
    }

    private func isNearBottom() -> Bool {
        let visible = scroll.contentView.documentVisibleRect
        let height = table.frame.height
        guard height > visible.height else {
            return true
        }
        return visible.maxY >= height - stickyBottom
    }

    private func scrollToBottom() {
        guard table.numberOfRows > 0 else {
            return
        }
        table.scrollRowToVisible(table.numberOfRows - 1)
        table.layoutSubtreeIfNeeded()
        if table.frame.height > scroll.contentView.bounds.height {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: table.frame.height - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { messages.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: ChatMessageCell.identifier, owner: nil) as? ChatMessageCell) ?? ChatMessageCell()
        let message = messages[row]
        cell.show(message.text, speaker: message.role == .user ? "You" : assistant, waiting: message.id == replyID && message.text.isEmpty)
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
