import AppKit
import OddFrogCore

@MainActor
final class HotkeyRecorder: NSControl {
    var hotkey: Hotkey? { didSet { needsDisplay = true } }
    var onRecord: ((Hotkey) -> Void)?
    private var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 24) }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func becomeFirstResponder() -> Bool { true }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            if event.keyCode == 49 || event.keyCode == 36 {
                recording = true
            } else {
                super.keyDown(with: event)
            }
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.isEmpty {
            recording = false
            window?.makeFirstResponder(nil)
            return
        }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= Hotkey.cmdKey }
        if flags.contains(.shift) { modifiers |= Hotkey.shiftKey }
        if flags.contains(.option) { modifiers |= Hotkey.optionKey }
        if flags.contains(.control) { modifiers |= Hotkey.controlKey }
        guard let recorded = Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
            NSSound.beep()
            return
        }
        recording = false
        window?.makeFirstResponder(nil)
        onRecord?(recorded)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
        let text = recording ? "Press keys… (Esc cancels)" : (hotkey?.description ?? "Click to record")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: recording ? .regular : .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}
