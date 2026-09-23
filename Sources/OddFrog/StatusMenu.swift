import AppKit
import OddFrogCore
import ServiceManagement

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()

    var hotkey = Hotkey.default
    var lastFailure: String?
    var onCancelAction: (() -> Void)?
    var onRetryMigration: (() -> Void)?
    var onShow: (() -> Void)?
    var onReloadConfig: (() -> Void)?
    var onReloadPlugins: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onRescan: (() -> Void)?
    var onToggleLogin: (() -> Void)?
    var onSettings: (() -> Void)?
    var onOpenLog: (() -> Void)?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "Odd Frog")
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if onRetryMigration != nil { menu.addItem(action("Retry Migration", #selector(retryMigration))) }
        if onCancelAction != nil { menu.addItem(action("Cancel Plugin Action", #selector(cancelAction))) }
        let showItem = action("Show", #selector(show))
        showItem.keyEquivalent = hotkey.keyEquivalent
        showItem.keyEquivalentModifierMask = keyEquivalentModifiers
        menu.addItem(showItem)
        menu.addItem(.separator())
        if let lastFailure {
            let firstLine = lastFailure.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? lastFailure
            let truncated = firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
            let failure = action("Copy Last Failure", #selector(copyFailure))
            failure.subtitle = truncated
            failure.toolTip = lastFailure
            menu.addItem(failure)
            menu.addItem(.separator())
        }
        let settings = action("Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(action("Reload Config", #selector(reload)))
        menu.addItem(action("Reload Plugins", #selector(reloadPlugins)))
        menu.addItem(action("Open Config", #selector(openConfig)))
        menu.addItem(action("Open Log", #selector(openLog)))
        menu.addItem(action("Refresh Catalogs", #selector(rescan)))
        menu.addItem(.separator())
        let login = action("Launch at Login", #selector(toggleLogin))
        login.state = LoginItem.status == .enabled ? .on : .off
        login.subtitle = loginNote
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Odd Frog", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private var loginNote: String? {
        switch LoginItem.status {
        case .requiresApproval: "Approve in System Settings"
        case .notFound: "Install to ~/Applications first"
        default: nil
        }
    }

    private var keyEquivalentModifiers: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if hotkey.modifiers & Hotkey.cmdKey != 0 { mask.insert(.command) }
        if hotkey.modifiers & Hotkey.optionKey != 0 { mask.insert(.option) }
        if hotkey.modifiers & Hotkey.controlKey != 0 { mask.insert(.control) }
        if hotkey.modifiers & Hotkey.shiftKey != 0 { mask.insert(.shift) }
        return mask
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func cancelAction() { onCancelAction?(); onCancelAction = nil }
    @objc private func retryMigration() { onRetryMigration?() }
    @objc private func show() { onShow?() }
    @objc private func openSettings() { onSettings?() }
    @objc private func reload() { onReloadConfig?() }
    @objc private func reloadPlugins() { onReloadPlugins?() }
    @objc private func openConfig() { onOpenConfig?() }
    @objc private func openLog() { onOpenLog?() }
    @objc private func rescan() { onRescan?() }
    @objc private func toggleLogin() { onToggleLogin?() }

    @objc private func copyFailure() {
        guard let lastFailure else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastFailure, forType: .string)
    }
}
