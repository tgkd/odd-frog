import AppKit
import OddFrogCore
import ServiceManagement

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()

    var hotkeyDescription = ""
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
        let image = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "Odd Frog")
        image?.isTemplate = true
        item.button?.image = image
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if onRetryMigration != nil { menu.addItem(action("Retry Migration", #selector(retryMigration))) }
        if onCancelAction != nil { menu.addItem(action("Cancel Plugin Action", #selector(cancelAction))) }
        menu.addItem(action("Show  \(hotkeyDescription)", #selector(show)))
        menu.addItem(.separator())
        if let lastFailure {
            let firstLine = lastFailure.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? lastFailure
            let truncated = firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
            let failure = action("Last failure: \(truncated)", #selector(copyFailure))
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
        let login = action(loginTitle, #selector(toggleLogin))
        login.state = LoginItem.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Odd Frog", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private var loginTitle: String {
        switch LoginItem.status {
        case .requiresApproval: "Launch at Login (approve in System Settings…)"
        case .notFound: "Launch at Login (install to ~/Applications first)"
        default: "Launch at Login"
        }
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
