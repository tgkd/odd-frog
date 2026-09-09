import AppKit
import OddFrogCore

@MainActor
final class LinkManagerController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onApply: ((CommandItem?, LinkDraft?) throws -> [CommandItem])?
    private var links: [CommandItem] = []
    private var original: CommandItem?
    private let table = NSTableView()
    private let nameField = NSTextField()
    private let urlField = NSTextField()
    private let aliasesField = NSTextField()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let saveButton = NSButton(title: "Add Link", target: nil, action: nil)
    private let editorTitle = NSTextField(labelWithString: "New link")

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 490),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Manage Links"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func present(links: [CommandItem], for parent: NSWindow) {
        guard let window, window.sheetParent == nil else { return }
        self.links = links
        table.reloadData()
        newLink()
        parent.beginSheet(window)
        window.makeFirstResponder(nameField)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "Links")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let helper = NSTextField(wrappingLabelWithString: "Web links open in your default browser. App links open in the app registered for that URL. Put {query} in a URL to insert what you type after the alias, for example gh odd-frog.")
        helper.font = .systemFont(ofSize: 12)
        helper.textColor = .secondaryLabelColor
        let add = NSButton(title: "New Link", target: self, action: #selector(newLink))
        deleteButton.target = self
        deleteButton.action = #selector(deleteLink)
        let toolbar = NSStackView(views: [add, deleteButton])
        toolbar.spacing = 8
        for button in [add, deleteButton, saveButton] { button.bezelStyle = .rounded }

        for (id, caption, width) in [("name", "Name", 150.0), ("url", "URL", 245.0), ("aliases", "Aliases", 120.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = caption
            column.width = width
            table.addTableColumn(column)
        }
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 28
        table.style = .inset
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        editorTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        let name = fieldBlock("Name", field: nameField, placeholder: "GitHub")
        let address = fieldBlock("URL", field: urlField, placeholder: "https://github.com or obsidian://open")
        let aliases = fieldBlock("Aliases (comma separated)", field: aliasesField, placeholder: "gh, github")
        let fields = NSStackView(views: [name, address, aliases])
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 10
        for field in [name, address, aliases] { field.widthAnchor.constraint(equalTo: fields.widthAnchor).isActive = true }
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        saveButton.target = self
        saveButton.action = #selector(saveLink)
        saveButton.keyEquivalent = "\r"
        let done = NSButton(title: "Done", target: self, action: #selector(closeManager))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [done, saveButton])
        buttons.spacing = 8

        for view in [title, helper, toolbar, scroll, editorTitle, fields, errorLabel, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            helper.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            helper.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            helper.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            toolbar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            toolbar.topAnchor.constraint(equalTo: helper.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: helper.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scroll.heightAnchor.constraint(equalToConstant: 110),
            editorTitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            editorTitle.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 14),
            fields.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            fields.trailingAnchor.constraint(equalTo: helper.trailingAnchor),
            fields.topAnchor.constraint(equalTo: editorTitle.bottomAnchor, constant: 10),
            errorLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: helper.trailingAnchor),
            errorLabel.topAnchor.constraint(equalTo: fields.bottomAnchor, constant: 6),
            errorLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: errorLabel.bottomAnchor, constant: 8),
            buttons.trailingAnchor.constraint(equalTo: helper.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        window?.setContentSize(NSSize(width: 580, height: 490))
    }

    private func fieldBlock(_ title: String, field: NSTextField, placeholder: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        field.placeholderString = placeholder
        field.setAccessibilityLabel(title)
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        let stack = NSStackView(views: [label, field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        field.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return stack
    }

    @objc private func newLink() {
        table.deselectAll(nil)
        original = nil
        nameField.stringValue = ""
        urlField.stringValue = ""
        aliasesField.stringValue = ""
        errorLabel.stringValue = ""
        editorTitle.stringValue = "New link"
        saveButton.title = "Add Link"
        deleteButton.isEnabled = false
        window?.makeFirstResponder(nameField)
    }

    @objc private func saveLink() {
        let draft = LinkDraft(name: nameField.stringValue, url: urlField.stringValue, aliases: aliasesField.stringValue)
        do {
            guard let onApply else { return }
            var saved = try draft.command()
            if let original { saved.stableID = original.stableID }
            links = try onApply(original, draft)
            table.reloadData()
            if let row = links.firstIndex(where: { $0.id == saved.id }) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                table.scrollRowToVisible(row)
                loadSelection()
            }
            errorLabel.stringValue = ""
        } catch {
            errorLabel.stringValue = (error as? ConfigError)?.description ?? error.localizedDescription
        }
    }

    @objc private func deleteLink() {
        guard let original, let window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(original.name)”?"
        alert.informativeText = "This removes the link and its aliases from the launcher."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            do {
                guard let onApply else { return }
                links = try onApply(original, nil)
                table.reloadData()
                newLink()
            } catch {
                errorLabel.stringValue = (error as? ConfigError)?.description ?? error.localizedDescription
            }
        }
    }

    @objc private func closeManager() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
    }

    private func loadSelection() {
        let row = table.selectedRow
        guard links.indices.contains(row) else { return }
        original = links[row]
        nameField.stringValue = links[row].name
        if case .url(let url) = links[row].action { urlField.stringValue = URLTemplate.display(url) }
        aliasesField.stringValue = links[row].aliases.joined(separator: ", ")
        editorTitle.stringValue = "Edit link"
        saveButton.title = "Save Changes"
        deleteButton.isEnabled = true
        errorLabel.stringValue = ""
    }

    func tableViewSelectionDidChange(_ notification: Notification) { loadSelection() }
    func numberOfRows(in tableView: NSTableView) -> Int { links.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let link = links[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "name": text = link.name
        case "url": if case .url(let url) = link.action { text = URLTemplate.display(url) } else { text = "" }
        default: text = link.aliases.joined(separator: ", ")
        }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = label
        cell.addSubview(label)
        cell.toolTip = text
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
