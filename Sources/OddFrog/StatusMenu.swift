import AppKit
import OddFrogCore
import ServiceManagement

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()

    var hotkeyDescription = ""
    var lastFailure: String?
    var onShow: (() -> Void)?
    var onReloadConfig: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onRescan: (() -> Void)?
    var onToggleLogin: (() -> Void)?
    var onSettings: (() -> Void)?

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
        menu.addItem(action("Show  \(hotkeyDescription)", #selector(show)))
        menu.addItem(.separator())
        if let lastFailure {
            let failure = NSMenuItem(title: "Last failure: \(lastFailure)", action: nil, keyEquivalent: "")
            failure.isEnabled = false
            menu.addItem(failure)
            menu.addItem(.separator())
        }
        let settings = action("Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(action("Reload Config", #selector(reload)))
        menu.addItem(action("Open Config", #selector(openConfig)))
        menu.addItem(action("Rescan Apps", #selector(rescan)))
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

    @objc private func show() { onShow?() }
    @objc private func openSettings() { onSettings?() }
    @objc private func reload() { onReloadConfig?() }
    @objc private func openConfig() { onOpenConfig?() }
    @objc private func rescan() { onRescan?() }
    @objc private func toggleLogin() { onToggleLogin?() }
}
