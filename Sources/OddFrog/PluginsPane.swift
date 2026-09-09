import AppKit
import OddFrogCore

@MainActor
final class PluginsPane: NSView {
    var onToggle: ((String, Bool) -> Void)?
    var onReload: (() -> Void)?
    private let stack = NSStackView()
    private var ids: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let reload = NSButton(title: "Reload Plugins", target: self, action: #selector(reloadPlugins))
        reload.bezelStyle = .rounded
        let helper = NSTextField(wrappingLabelWithString: "Enable a plugin, then type its keyword in the launcher. Calendar and Reminders permission is requested when you choose the Allow access row.")
        helper.textColor = .secondaryLabelColor
        helper.font = .systemFont(ofSize: 12)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        scroll.documentView = stack
        for view in [reload, helper, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            reload.topAnchor.constraint(equalTo: topAnchor),
            reload.leadingAnchor.constraint(equalTo: leadingAnchor),
            helper.topAnchor.constraint(equalTo: reload.bottomAnchor, constant: 12),
            helper.leadingAnchor.constraint(equalTo: leadingAnchor),
            helper.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: helper.bottomAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(packages: [PluginPackage], settings: [PluginSetting], failures: [String: String], errors: [String]) {
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        ids = packages.map { $0.manifest.id }
        for (index, package) in packages.enumerated() {
            let enabled = package.isEnabled(settings: settings)
            let button = NSButton(checkboxWithTitle: package.manifest.name, target: self, action: #selector(toggled(_:)))
            button.tag = index
            button.state = enabled ? .on : .off
            stack.addArrangedSubview(button)
            let source = package.bundled ? "Bundled" : "User installed"
            let state = enabled ? (failures[package.manifest.id] ?? "Ready") : "Disabled"
            let text = "\(package.manifest.keyword) · \(source) · \(state)"
            addLabel(text, error: enabled && failures[package.manifest.id] != nil)
        }
        for error in errors { addLabel(error, error: true) }
        if packages.isEmpty, errors.isEmpty { addLabel("No plugins found. Build the app bundle to include bundled plugins.", error: false) }
    }

    private func addLabel(_ text: String, error: Bool) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = error ? .systemRed : .secondaryLabelColor
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
    }

    @objc private func toggled(_ sender: NSButton) {
        guard ids.indices.contains(sender.tag) else { return }
        onToggle?(ids[sender.tag], sender.state == .on)
    }

    @objc private func reloadPlugins() { onReload?() }
}
