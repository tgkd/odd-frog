import AppKit
import OddFrogCore

@MainActor
final class HotkeyRecorder: NSControl {
    var hotkey: Hotkey? { didSet { needsDisplay = true } }
    var onRecord: ((Hotkey) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var conflict = false {
        didSet {
            if !conflict { rejected = nil }
            needsDisplay = true
        }
    }

    private var rejected: Hotkey?
    private var recording = false {
        didSet {
            guard recording != oldValue else { return }
            needsDisplay = true
            onRecordingChanged?(recording)
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 22) }
    override var focusRingMaskBounds: NSRect { bounds }

    override var focusRingType: NSFocusRingType {
        get { .exterior }
        set {}
    }

    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill() }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startRecording()
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
                startRecording()
            } else {
                super.keyDown(with: event)
            }
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.isEmpty, event.keyCode == 53 || event.keyCode == 51 || event.keyCode == 117 {
            cancelRecording()
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
        rejected = recorded
        recording = false
        window?.makeFirstResponder(nil)
        onRecord?(recorded)
    }

    private func startRecording() {
        conflict = false
        recording = true
    }

    private func cancelRecording() {
        recording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.shadowColor.withAlphaComponent(0.12)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1
        shadow.set()
        NSColor.controlColor.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        path.lineWidth = 1
        (conflict ? NSColor.systemRed : NSColor.separatorColor).setStroke()
        path.stroke()
        let text = recording ? "Type shortcut…" : ((conflict ? rejected : hotkey) ?? hotkey)?.description ?? ""
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: recording ? .regular : .medium),
            .foregroundColor: recording ? NSColor.tertiaryLabelColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: 10, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}
