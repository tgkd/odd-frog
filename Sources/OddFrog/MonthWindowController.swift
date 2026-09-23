import AppKit
import OddFrogPluginAPI

@MainActor
final class MonthWindowController: NSWindowController, NSWindowDelegate {
    private let picker = NSDatePicker()
    private var today = Date()
    private var observers: [any NSObjectProtocol] = []

    init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("month")
        super.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
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
        goToToday(nil)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(picker)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if !Calendar.current.isDate(Date(), inSameDayAs: today) {
            refresh()
        }
    }

    @objc func showPreviousMonth(_ sender: Any?) {
        move(by: -1)
    }

    @objc func showNextMonth(_ sender: Any?) {
        move(by: 1)
    }

    @objc func goToToday(_ sender: Any?) {
        today = Date()
        show(today)
    }

    private func move(by months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: picker.dateValue) else {
            return
        }
        show(next)
    }

    private func show(_ date: Date) {
        picker.dateValue = date
        picker.calendar = .autoupdatingCurrent
        picker.locale = .autoupdatingCurrent
        picker.timeZone = .autoupdatingCurrent
    }

    private func refresh() {
        let followed = Calendar.current.isDate(picker.dateValue, inSameDayAs: today)
        today = Date()
        show(followed ? today : picker.dateValue)
    }

    private func buildContent() {
        guard let content = window?.contentView else {
            return
        }
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        show(today)
        picker.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: content.layoutMarginsGuide.topAnchor),
            picker.leadingAnchor.constraint(equalTo: content.layoutMarginsGuide.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: content.layoutMarginsGuide.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: content.layoutMarginsGuide.bottomAnchor),
        ])
        window?.setContentSize(content.fittingSize)
    }
}
