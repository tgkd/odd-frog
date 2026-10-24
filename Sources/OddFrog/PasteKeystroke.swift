import AppKit
import Carbon

@MainActor
enum PasteKeystroke {
    // The launcher panel has just been ordered out; until the window server hands keyboard focus
    // back to the previous app, a posted ⌘V lands in Odd Frog and is dropped.
    private static let focusDelay: Duration = .milliseconds(120)
    // Left-⌘ device bit: some apps ignore ⌘ shortcuts whose flags carry no physical key.
    private static let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x8)

    /// Returns false when Odd Frog may not post keystrokes yet; the system prompt for Accessibility opens once.
    static func send() -> Bool {
        guard WindowManager.hasAccess else {
            Log.write("paste skipped: no Accessibility access")
            WindowManager.requestAccess()
            return false
        }
        Task { @MainActor in
            try? await Task.sleep(for: focusDelay)
            post()
        }
        return true
    }

    private static func post() {
        let target = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            Log.write("paste failed: could not create ⌘V events")
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Log.write("paste posted to \(target), odd frog key window: \(NSApp.keyWindow != nil)")
    }
}
