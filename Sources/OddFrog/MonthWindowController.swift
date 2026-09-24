import AppKit
import OddFrogCore
import OddFrogPluginAPI
import SwiftUI

@MainActor
final class MonthWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let contentSize = NSSize(width: 780, height: 620)
    private static let minimumSize = NSSize(width: 400, height: 360)
    private static let mode = NSToolbarItem.Identifier("mode")
    private static let previous = NSToolbarItem.Identifier("previous")
    private static let today = NSToolbarItem.Identifier("today")
    private static let next = NSToolbarItem.Identifier("next")

    private let model = CalendarWindowModel(browser: CalendarBrowser(now: Date(), calendar: .current))
    private var modeGroup: NSToolbarItemGroup?
    private var observers: [any NSObjectProtocol] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = Self.minimumSize
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "calendar")
        toolbar.delegate = self
        window.toolbar = toolbar

        let host = NSHostingController(rootView: CalendarView(model: model, open: { [weak self] month in
            self?.update { $0.open(month: month) }
        }))
        host.sizingOptions = []
        window.contentViewController = host

        window.setContentSize(Self.contentSize)
        window.center()
        window.setFrameAutosaveName("calendar")

        let names: [Notification.Name] = [.NSCalendarDayChanged, .NSSystemTimeZoneDidChange,
                                          NSLocale.currentLocaleDidChangeNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    func present(_ view: PluginView) {
        window?.title = view.title
        update { $0.present(now: Date(), calendar: .current) }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    @objc func showMonthView(_ sender: Any?) {
        update { $0.show(.month) }
    }

    @objc func showYearView(_ sender: Any?) {
        update { $0.show(.year) }
    }

    @objc func showPrevious(_ sender: Any?) {
        update { $0.step(by: -1) }
    }

    @objc func showNext(_ sender: Any?) {
        update { $0.step(by: 1) }
    }

    @objc func goToToday(_ sender: Any?) {
        update { $0.goToToday(now: Date(), calendar: .current) }
    }

    @objc private func modeChanged(_ sender: Any?) {
        let mode: CalendarBrowser.Mode = modeGroup?.selectedIndex == 1 ? .year : .month
        update { $0.show(mode) }
    }

    private func update(_ change: (inout CalendarBrowser) -> Void) {
        change(&model.browser)
        modeGroup?.selectedIndex = model.browser.mode == .month ? 0 : 1
    }

    private func refresh() {
        update { $0.refresh(now: Date(), calendar: .current) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.mode, .flexibleSpace, Self.previous, Self.today, Self.next]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.mode, .flexibleSpace, Self.previous, Self.today, Self.next]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.mode:
            let group = NSToolbarItemGroup(itemIdentifier: itemIdentifier, titles: ["Month", "Year"], selectionMode: .selectOne, labels: ["Month", "Year"], target: self, action: #selector(modeChanged(_:)))
            group.selectedIndex = model.browser.mode == .month ? 0 : 1
            modeGroup = group
            return group
        case Self.previous:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Previous"
            item.toolTip = "Previous"
            item.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")
            item.target = self
            item.action = #selector(showPrevious(_:))
            return item
        case Self.today:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.title = "Today"
            item.label = "Today"
            item.target = self
            item.action = #selector(goToToday(_:))
            return item
        case Self.next:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Next"
            item.toolTip = "Next"
            item.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")
            item.target = self
            item.action = #selector(showNext(_:))
            return item
        default:
            return nil
        }
    }
}
