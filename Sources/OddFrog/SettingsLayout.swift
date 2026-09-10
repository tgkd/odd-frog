import AppKit

@MainActor
enum SettingsLayout {
    static func settingRow(title: String, subtitle: NSTextField, control: NSView) -> NSView {
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
        if let stack = control as? NSStackView {
            stack.setHuggingPriority(.required, for: .horizontal)
            for view in stack.arrangedSubviews {
                view.setContentHuggingPriority(.required, for: .horizontal)
            }
        }

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

    static func groupedBox(_ rows: [NSView]) -> NSView {
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

    static func hairline() -> NSView {
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

    static func sectionHeader(_ text: String) -> NSView {
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

    static func stackedPane(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    static func groupTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        field.isSelectable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    static func helper(_ text: String = "") -> NSTextField {
        let field = NSTextField(labelWithString: text)
        style(helper: field)
        return field
    }

    static func style(helper field: NSTextField) {
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.isSelectable = false
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
    }

    static func smallSwitch(target: AnyObject?, action: Selector?) -> NSSwitch {
        let control = NSSwitch()
        control.controlSize = .small
        control.target = target
        control.action = action
        return control
    }

    static func smallButton(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        return button
    }
}
