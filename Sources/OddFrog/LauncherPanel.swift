import AppKit

@MainActor
final class LauncherPanel: NSPanel {
    static let width: CGFloat = 560

    var onResignKey: (() -> Void)?
    var onKeyEquivalent: ((NSEvent) -> Bool)?

    private var expectedTop: NSPoint?

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(didMove(_:)), name: NSWindow.didMoveNotification, object: self
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
        let target: NSRect
        if let top = LauncherPlacement.saved, NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: top.x, y: top.y - 1)) }) {
            target = NSRect(x: top.x - Self.width / 2, y: top.y - height, width: Self.width, height: height)
        } else {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
            let visible = screen.visibleFrame
            let x = visible.midX - Self.width / 2
            let y = visible.maxY - visible.height * 0.25 - height
            target = NSRect(x: x, y: y, width: Self.width, height: height)
        }
        expectedTop = NSPoint(x: target.midX, y: target.maxY)
        setFrame(target, display: true)
        makeKeyAndOrderFront(nil)
    }

    func resize(height: CGFloat) {
        var target = frame
        target.origin.y -= height - target.height
        target.size.height = height
        expectedTop = NSPoint(x: target.midX, y: target.maxY)
        setFrame(target, display: true)
    }

    func resetPlacement() {
        LauncherPlacement.clear()
        expectedTop = nil
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
    }

    @objc private func didResignKey(_ note: Notification) {
        onResignKey?()
    }

    @objc private func didMove(_ note: Notification) {
        guard isVisible else { return }
        let top = NSPoint(x: frame.midX, y: frame.maxY)
        guard let expectedTop else {
            LauncherPlacement.save(top)
            self.expectedTop = top
            return
        }
        if abs(expectedTop.x - top.x) > 0.5 || abs(expectedTop.y - top.y) > 0.5 {
            LauncherPlacement.save(top)
            self.expectedTop = top
        }
    }
}
