import AppKit
import OddFrogCore
import OddFrogPluginAPI

@MainActor
final class MonthWindowController: NSWindowController, NSWindowDelegate {
    private final class DayCell: NSView {
        private let marker = NSView()
        private let label = NSTextField(labelWithString: "")
        private var day: MonthGrid.Day?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            marker.wantsLayer = true
            marker.isHidden = true
            marker.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 13)
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(marker)
            addSubview(label)
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: 40),
                heightAnchor.constraint(equalToConstant: 32),
                marker.centerXAnchor.constraint(equalTo: centerXAnchor),
                marker.centerYAnchor.constraint(equalTo: centerYAnchor),
                marker.widthAnchor.constraint(equalToConstant: 26),
                marker.heightAnchor.constraint(equalToConstant: 26),
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            setAccessibilityElement(true)
            setAccessibilityRole(.staticText)
        }

        required init?(coder: NSCoder) { nil }

        func show(_ day: MonthGrid.Day) {
            self.day = day
            label.stringValue = day.number
            setAccessibilityLabel(day.label)
            configure()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            configure()
        }

        private func configure() {
            guard let day else {
                return
            }
            marker.isHidden = !day.isToday
            marker.layer?.cornerRadius = 13
            effectiveAppearance.performAsCurrentDrawingAppearance {
                marker.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            }
            if day.isToday {
                label.textColor = .white
            } else {
                label.textColor = day.inMonth ? .labelColor : .tertiaryLabelColor
            }
        }
    }

    private final class KeyView: NSView {
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?
        var onToday: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            if modifiers.isEmpty, event.charactersIgnoringModifiers?.lowercased() == "t" {
                onToday?()
                return
            }
            interpretKeyEvents([event])
        }

        override func moveLeft(_ sender: Any?) {
            onPrevious?()
        }

        override func moveRight(_ sender: Any?) {
            onNext?()
        }

        override func cancelOperation(_ sender: Any?) {
            window?.performClose(nil)
        }
    }

    private let heading = NSTextField(labelWithString: "")
    private let keyView = KeyView()
    private var weekdayLabels: [NSTextField] = []
    private var cells: [DayCell] = []
    private var observers: [any NSObjectProtocol] = []
    private var anchor = Date()
    private var browsed = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("month")
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
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
        anchor = Date()
        browsed = false
        rebuild()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(keyView)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    @objc private func showPrevious() {
        move(by: -1)
    }

    @objc private func showNext() {
        move(by: 1)
    }

    @objc private func showToday() {
        anchor = Date()
        browsed = false
        rebuild()
    }

    private func move(by months: Int) {
        anchor = MonthGrid.shifted(anchor, months: months, calendar: .current)
        browsed = true
        rebuild()
    }

    private func refresh() {
        if !browsed {
            anchor = Date()
        }
        rebuild()
    }

    private func rebuild() {
        let grid = MonthGrid(month: anchor, today: Date(), calendar: .current)
        heading.stringValue = grid.heading
        for (label, symbol) in zip(weekdayLabels, grid.weekdays) {
            label.stringValue = symbol
        }
        for (cell, day) in zip(cells, grid.days) {
            cell.show(day)
        }
    }

    private func button(symbol: String, description: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.setAccessibilityLabel(description)
        return button
    }

    private func buildContent() {
        guard let content = window?.contentView else {
            return
        }
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.translatesAutoresizingMaskIntoConstraints = false

        let today = NSButton(title: "Today", target: self, action: #selector(showToday))
        today.bezelStyle = .rounded
        today.controlSize = .small
        today.font = .systemFont(ofSize: 11)
        let controls = NSStackView(views: [
            button(symbol: "chevron.left", description: "Previous month", action: #selector(showPrevious)),
            today,
            button(symbol: "chevron.right", description: "Next month", action: #selector(showNext)),
        ])
        controls.spacing = 4
        controls.translatesAutoresizingMaskIntoConstraints = false

        weekdayLabels = (0..<7).map { _ in
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            return label
        }
        cells = (0..<42).map { _ in DayCell() }
        var rows: [[NSView]] = [weekdayLabels]
        for week in 0..<6 {
            rows.append(Array(cells[(week * 7)..<(week * 7 + 7)]))
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 2
        grid.columnSpacing = 2
        grid.xPlacement = .center
        grid.yPlacement = .center
        grid.translatesAutoresizingMaskIntoConstraints = false

        keyView.onPrevious = { [weak self] in
            self?.move(by: -1)
        }
        keyView.onNext = { [weak self] in
            self?.move(by: 1)
        }
        keyView.onToday = { [weak self] in
            self?.showToday()
        }
        keyView.translatesAutoresizingMaskIntoConstraints = false
        keyView.addSubview(heading)
        keyView.addSubview(controls)
        keyView.addSubview(grid)
        content.addSubview(keyView)

        NSLayoutConstraint.activate([
            keyView.topAnchor.constraint(equalTo: content.topAnchor),
            keyView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            keyView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            keyView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            heading.topAnchor.constraint(equalTo: keyView.topAnchor, constant: 12),
            heading.leadingAnchor.constraint(equalTo: keyView.leadingAnchor, constant: 16),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor, constant: -8),
            controls.trailingAnchor.constraint(equalTo: keyView.trailingAnchor, constant: -16),
            controls.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            grid.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            grid.centerXAnchor.constraint(equalTo: keyView.centerXAnchor),
        ])
    }
}
