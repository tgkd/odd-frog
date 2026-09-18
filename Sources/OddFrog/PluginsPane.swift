import AppKit
import OddFrogCore
import OddFrogPluginAPI

@MainActor
final class PluginsPane: NSView {
    var onToggle: ((String, Bool) -> Void)?
    var onReload: (() -> Void)?
    var onSetting: ((String, String, JSONValue) -> Void)?
    var onTrigger: ((String, String?) -> Void)?
    var onManageLinks: (() -> Void)?

    private let scroll = NSScrollView()
    private let content = NSStackView()
    private let helper = SettingsLayout.helper("Local packages are trusted code. Enable user packages explicitly; changes to a package restart its providers.")
    private let message = SettingsLayout.helper()
    private var bindings: [SettingBinding] = []
    private var lastPackages: [PluginPackage] = []
    private var lastSettings: [PluginSetting] = []
    private var lastFailures: [String: String] = [:]
    private var lastErrors: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.distribution = .fill
        content.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        helper.lineBreakMode = .byTruncatingTail
        helper.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        message.textColor = .systemRed
        message.isHidden = true
        let reload = NSButton(title: "Reload Plugins", target: self, action: #selector(reloadPlugins))
        reload.bezelStyle = .rounded
        reload.controlSize = .regular
        reload.font = .systemFont(ofSize: 13)
        reload.setContentCompressionResistancePriority(.required, for: .horizontal)
        reload.setContentHuggingPriority(.required, for: .horizontal)
        let footer = NSStackView(views: [helper, reload])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroll)
        addSubview(message)
        addSubview(footer)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -2),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
            message.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            message.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 8),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(packages: [PluginPackage], settings: [PluginSetting], failures: [String: String], errors: [String]) {
        guard packages != lastPackages || settings != lastSettings || failures != lastFailures || errors != lastErrors else { return }
        lastPackages = packages
        lastSettings = settings
        lastFailures = failures
        lastErrors = errors
        for view in content.arrangedSubviews {
            content.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bindings = []
        message.isHidden = true

        var sections: [NSView] = []
        let bundled = packages.filter(\.bundled)
        let installed = packages.filter { !$0.bundled }
        if !installed.isEmpty, !bundled.isEmpty { sections.append(SettingsLayout.sectionHeader("Bundled")) }
        sections += bundled.map { box(for: $0, settings: settings, failures: failures) }
        if !installed.isEmpty {
            sections.append(SettingsLayout.sectionHeader("Installed"))
            sections += installed.map { box(for: $0, settings: settings, failures: failures) }
        }
        if packages.isEmpty, errors.isEmpty {
            sections.append(SettingsLayout.helper("No plugins found. Build the app bundle to include bundled plugins."))
        }
        for error in errors {
            let label = NSTextField(wrappingLabelWithString: error)
            SettingsLayout.style(helper: label)
            label.lineBreakMode = .byWordWrapping
            label.textColor = .systemRed
            sections.append(label)
        }
        for view in sections {
            content.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
    }

    private func box(for package: PluginPackage, settings: [PluginSetting], failures: [String: String]) -> NSView {
        let manifest = package.manifest
        let enabled = package.isEnabled(settings: settings)
        let failure = failures[manifest.id]
        let toggle = SettingBinding { [weak self] value in self?.onToggle?(manifest.id, value.bool ?? false) }
        bindings.append(toggle)
        let control = SettingsLayout.smallSwitch(target: toggle, action: #selector(SettingBinding.flip(_:)))
        control.state = enabled ? .on : .off
        let state = failure ?? (enabled ? "Ready" : "Off")
        let source = package.bundled ? "Bundled" : LauncherItem.abbreviate(package.directory.path)
        let status = SettingsLayout.helper("\(manifest.version) · \(source) · \(state)")
        if failure != nil { status.textColor = .systemRed }
        var rows: [NSView] = [SettingsLayout.settingRow(title: manifest.name, subtitle: status, control: control)]

        if let trigger = manifest.trigger {
            rows.append(SettingsLayout.hairline())
            rows.append(triggerRow(for: package, trigger: trigger, settings: settings))
        }
        let values = package.setting(in: settings)?.values ?? [:]
        for definition in manifest.settings {
            rows.append(SettingsLayout.hairline())
            rows.append(row(for: definition, value: values[definition.key] ?? definition.defaultValue, package: package))
        }
        if enabled, failure == nil, manifest.capabilities.contains("links.manage@1") {
            let button = SettingsLayout.smallButton("Manage Links…", target: self, action: #selector(manageLinks))
            rows.append(SettingsLayout.hairline())
            rows.append(SettingsLayout.settingRow(title: "Links", subtitle: SettingsLayout.helper("Add, edit and remove URL commands."), control: button))
        }
        return SettingsLayout.groupedBox(rows)
    }

    private func triggerRow(for package: PluginPackage, trigger: PluginTrigger, settings: [PluginSetting]) -> NSView {
        let manifest = package.manifest
        let stored = package.setting(in: settings)?.trigger
        let resolved = (try? package.trigger(in: settings))?.text ?? trigger.text
        let field = NSTextField()
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = trigger.text
        field.stringValue = resolved
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let binding = SettingBinding { [weak self, weak field] value in
            guard let self else {
                return
            }
            var text = (value.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if case .keyword = trigger {
                text = text.lowercased()
            }
            if text.isEmpty || text == trigger.text {
                message.isHidden = true
                field?.stringValue = trigger.text
                if stored != nil {
                    onTrigger?(manifest.id, nil)
                }
                return
            }
            do {
                let candidate = try trigger.replacing(text)
                if let other = package.triggerConflict(candidate, among: lastPackages, settings: lastSettings) {
                    message.stringValue = "\(manifest.name): \(trigger.label) '\(text)' is already used by \(other.manifest.name)."
                    message.isHidden = false
                    field?.stringValue = resolved
                    return
                }
                message.isHidden = true
                if text != resolved {
                    onTrigger?(manifest.id, text)
                }
            } catch {
                message.stringValue = "\(manifest.name): \(error)"
                message.isHidden = false
                field?.stringValue = resolved
            }
        }
        bindings.append(binding)
        field.delegate = binding
        let subtitle = SettingsLayout.helper("Type this first in the launcher to use \(manifest.name).")
        return SettingsLayout.settingRow(title: trigger.label, subtitle: subtitle, control: field)
    }

    private func row(for definition: PluginSettingDefinition, value: JSONValue, package: PluginPackage) -> NSView {
        let binding = SettingBinding { [weak self] value in
            guard let self else { return }
            do {
                try definition.validate(value)
                message.isHidden = true
                onSetting?(package.manifest.id, definition.key, value)
            } catch {
                message.stringValue = "\(package.manifest.name): \(error)"
                message.isHidden = false
            }
        }
        binding.kind = definition.type
        bindings.append(binding)
        let subtitle = SettingsLayout.helper()
        let control: NSView
        switch definition.type {
        case .boolean:
            let field = SettingsLayout.smallSwitch(target: binding, action: #selector(SettingBinding.flip(_:)))
            field.state = value.bool == true ? .on : .off
            control = field
        case .choice:
            let field = NSPopUpButton()
            field.controlSize = .small
            field.font = .systemFont(ofSize: 11)
            field.addItems(withTitles: definition.choices ?? [])
            field.selectItem(withTitle: value.string ?? "")
            field.target = binding
            field.action = #selector(SettingBinding.choose(_:))
            control = field
        case .folders:
            binding.folders = (value.array ?? []).compactMap(\.string)
            subtitle.stringValue = binding.folders.isEmpty ? "No folders yet." : binding.folders.map(LauncherItem.abbreviate).joined(separator: "\n")
            let add = SettingsLayout.smallButton("Add…", target: binding, action: #selector(SettingBinding.addFolders(_:)))
            let clear = SettingsLayout.smallButton("Clear", target: binding, action: #selector(SettingBinding.clearFolders))
            clear.isEnabled = !binding.folders.isEmpty
            let buttons = NSStackView(views: [add, clear])
            buttons.orientation = .horizontal
            buttons.spacing = 6
            control = buttons
        case .string, .number:
            let field = NSTextField()
            field.bezelStyle = .roundedBezel
            field.usesSingleLineMode = true
            field.lineBreakMode = .byTruncatingTail
            field.font = .systemFont(ofSize: 13)
            field.placeholderString = definition.defaultValue.string ?? definition.defaultValue.number.map { Self.format($0) } ?? ""
            field.stringValue = value.string ?? value.number.map { Self.format($0) } ?? ""
            field.delegate = binding
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: definition.type == .number ? 90 : 290).isActive = true
            if definition.type == .number, let minimum = definition.minimum, let maximum = definition.maximum {
                subtitle.stringValue = "\(Self.format(minimum)) – \(Self.format(maximum))"
            }
            control = field
        }
        return SettingsLayout.settingRow(title: definition.title, subtitle: subtitle, control: control)
    }

    private static func format(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }

    @objc private func reloadPlugins() { onReload?() }
    @objc private func manageLinks() { onManageLinks?() }
}

@MainActor
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class SettingBinding: NSObject, NSTextFieldDelegate {
    var kind = PluginSettingDefinition.Kind.string
    var folders: [String] = []
    let commit: (JSONValue) -> Void

    init(_ commit: @escaping (JSONValue) -> Void) { self.commit = commit }

    @objc func flip(_ control: NSSwitch) { commit(.bool(control.state == .on)) }
    @objc func choose(_ button: NSPopUpButton) { commit(.string(button.titleOfSelectedItem ?? "")) }

    @objc func addFolders(_ sender: NSButton) {
        guard let window = sender.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            var seen = Set(folders)
            for url in panel.urls {
                var path = url.path
                if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
                if seen.insert(path).inserted { folders.append(path) }
            }
            commit(.array(folders.map(JSONValue.string)))
        }
    }

    @objc func clearFolders() {
        folders = []
        commit(.array([]))
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        switch kind {
        case .number: commit(Double(field.stringValue.trimmingCharacters(in: .whitespaces)).map(JSONValue.number) ?? .null)
        default: commit(.string(field.stringValue))
        }
    }
}
