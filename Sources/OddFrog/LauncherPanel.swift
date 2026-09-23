import AppKit

@MainActor
final class LauncherPanel: NSPanel {
    static let width: CGFloat = 560

    var onResignKey: (() -> Void)?
    var onKeyEquivalent: ((NSEvent) -> Bool)?

    init(contentViewController controller: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 60),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .transient]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        contentViewController = controller
        NotificationCenter.default.addObserver(
            self, selector: #selector(didResignKey(_:)), name: NSWindow.didResignKeyNotification, object: self
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let onKeyEquivalent, onKeyEquivalent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func present(height: CGFloat) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = visible.midX - Self.width / 2
        let y = visible.maxY - visible.height * 0.25 - height
        let target = NSRect(x: x, y: y, width: Self.width, height: height)
        setFrame(target, display: true)
        makeKeyAndOrderFront(nil)
    }

    func resize(height: CGFloat) {
        var target = frame
        target.origin.y -= height - target.height
        target.size.height = height
        setFrame(target, display: true)
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
    }

    @objc private func didResignKey(_ note: Notification) {
        onResignKey?()
    }
}
