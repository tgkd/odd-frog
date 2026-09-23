import AppKit
import OddFrogCore

@MainActor
final class HotkeyRecorder: NSButton {
    var onRecord: ((Hotkey) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private var recording = false {
        didSet {
            state = recording ? .on : .off
            guard recording != oldValue else { return }
            onRecordingChanged?(recording)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.pushOnPushOff)
        target = self
        action = #selector(toggleRecording)
    }

    required init?(coder: NSCoder) { nil }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    @objc private func toggleRecording() {
        if state == .on {
            window?.makeFirstResponder(self)
            recording = true
        } else {
            cancelRecording()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            if event.keyCode == 49 || event.keyCode == 36 {
                performClick(nil)
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
        recording = false
        window?.makeFirstResponder(nil)
        onRecord?(recorded)
    }

    private func cancelRecording() {
        recording = false
        window?.makeFirstResponder(nil)
    }
}
