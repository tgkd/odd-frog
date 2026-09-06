import AppKit
import QuartzCore

@MainActor
final class LauncherPanel: NSPanel {
    static let width: CGFloat = 560
    static let animationDuration: TimeInterval = 0.14
    static let appearRise: CGFloat = 4

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
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentViewController = controller
        NotificationCenter.default.addObserver(
            self, selector: #selector(didResignKey(_:)), name: NSWindow.didResignKeyNotification, object: self
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let onKeyEquivalent, onKeyEquivalent(event) {
            return
        }
        super.sendEvent(event)
    }

    func present(height: CGFloat) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = visible.midX - Self.width / 2
        let y = visible.maxY - visible.height * 0.25 - height
        let target = NSRect(x: x, y: y, width: Self.width, height: height)
        guard !isVisible, !Self.prefersReducedMotion else {
            alphaValue = 1
            setFrame(target, display: true)
            makeKeyAndOrderFront(nil)
            return
        }
        var start = target
        start.origin.y -= Self.appearRise
        alphaValue = 0
        setFrame(start, display: false)
        makeKeyAndOrderFront(nil)
        animate { [weak self] in
            guard let self else { return }
            animator().alphaValue = 1
            animator().setFrame(target, display: true)
        }
    }

    func resize(height: CGFloat) {
        var target = frame
        target.origin.y -= height - target.height
        target.size.height = height
        guard isVisible, !Self.prefersReducedMotion else {
            setFrame(target, display: true)
            return
        }
        animate { [weak self] in
            self?.animator().setFrame(target, display: true)
        }
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        alphaValue = 1
    }

    private static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func animate(_ body: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            body()
        }
    }

    @objc private func didResignKey(_ note: Notification) {
        onResignKey?()
    }
}
