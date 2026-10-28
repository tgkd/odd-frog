import AppKit
import OddFrogCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    let pluginsPane = PluginsPaneModel()
    var onChange: ((OddFrogCore.Settings) -> Void)?
    var onAppearance: ((OddFrogCore.Settings.Appearance) -> Void)?
    var onApplyLink: ((CommandItem?, LinkDraft?) throws -> [CommandItem])?
    var onHotkey: ((Hotkey) -> Void)?
    var onNotifications: ((Bool) -> Void)?
    var links: [CommandItem] = []
    /// Item hotkeys declared in config, shown in the Items pane until an override replaces them.
    var defaultHotkeys: [String: Hotkey] {
        get { itemsPane.defaultHotkeys }
        set { itemsPane.defaultHotkeys = newValue }
    }
    /// Why an item's hotkey is not active, keyed by item id.
    var hotkeyConflicts: [String: String] {
        get { itemsPane.hotkeyConflicts }
        set { itemsPane.hotkeyConflicts = newValue }
    }

    private let linkManager = LinkManagerController()
    private let splitController = NSSplitViewController()
    private let sidebar = SettingsSidebarController()
    private let paneController = NSTabViewController()
    private let general = GeneralPaneModel()
    private let appearancePane = AppearancePaneModel()
    private let itemsPane: ItemsPaneController

    private var currentPane = SettingsPane.general

    init(icons: IconCache) {
        itemsPane = ItemsPaneController(icons: icons)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func present(settings: OddFrogCore.Settings, items: [LauncherItem], hotkey: Hotkey, focusing id: String? = nil) {
        itemsPane.settings = settings
        appearancePane.show(settings.appearance)
        showHotkey(hotkey)
        general.refreshLogin()
        general.refreshPlacement()
        general.showNotifications(settings.notifications.enabled)
        general.refreshNotificationAccess()
        let revealing = itemsPane.show(items: items, revealing: id)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if revealing, let id {
            showPane(.items)
            itemsPane.edit(itemID: id)
        } else {
            showPane(currentPane)
        }
    }

    func update(items: [LauncherItem]) {
        itemsPane.update(items: items)
    }

    func update(pluginSettings: [PluginSetting]) { itemsPane.settings.plugins = pluginSettings }

    func update(appearance: OddFrogCore.Settings.Appearance) {
        itemsPane.settings.appearance = appearance
        appearancePane.show(appearance)
    }

    func showHotkey(_ hotkey: Hotkey, note: String? = nil) {
        general.show(hotkey, note: note)
    }

    func select(_ pane: SettingsPane) { showPane(pane) }

    func manageLinks() {
        guard let window else { return }
        itemsPane.endEditing(commit: true)
        linkManager.onApply = onApplyLink
        linkManager.present(links: links, for: window)
    }

    private func buildContent() {
        guard let window else { return }
        sidebar.onSelect = { [weak self] pane in self?.showPane(pane) }
        general.onHotkey = { [weak self] hotkey in self?.onHotkey?(hotkey) }
        general.onNotifications = { [weak self] on in self?.onNotifications?(on) }
        itemsPane.onChange = { [weak self] in self?.onChange?($0) }
        appearancePane.onChange = { [weak self] appearance in self?.onAppearance?(appearance) }

        paneController.tabStyle = .unspecified
        let generalHost = NSHostingController(rootView: GeneralPaneView(model: general))
        generalHost.sizingOptions = []
        paneController.addChild(generalHost)
        let appearanceHost = NSHostingController(rootView: AppearancePaneView(model: appearancePane))
        appearanceHost.sizingOptions = []
        paneController.addChild(appearanceHost)
        paneController.addChild(itemsPane)
        let pluginsHost = NSHostingController(rootView: PluginsPaneView(model: pluginsPane))
        pluginsHost.sizingOptions = []
        paneController.addChild(pluginsHost)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(NSSplitViewItem(viewController: paneController))

        window.contentViewController = splitController
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 760, height: 560)
        window.center()
        showPane(.general)
    }

    private func showPane(_ pane: SettingsPane) {
        if currentPane == .items, pane != .items { itemsPane.endEditing(commit: true) }
        sidebar.focus()
        currentPane = pane
        sidebar.selected = pane
        paneController.selectedTabViewItemIndex = pane.rawValue
        window?.title = pane.title
        guard pane == .items else { return }
        itemsPane.focusFilter()
    }
}
