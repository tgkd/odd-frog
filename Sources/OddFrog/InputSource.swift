import Carbon

/// Keyboard input sources enabled in System Settings › Keyboard › Text Input.
@MainActor
enum InputSource {
    struct Choice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    static var choices: [Choice] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.compactMap { source in
            guard let id = string(source, kTISPropertyInputSourceID) else { return nil }
            return Choice(id: id, name: string(source, kTISPropertyLocalizedName) ?? id)
        }
    }

    static var currentID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return string(source, kTISPropertyInputSourceID)
    }

    @discardableResult
    static func select(_ id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return false }
        return TISSelectInputSource(source) == noErr
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

/// Selects the launcher's input source while it is open and gives the previous one back on close.
@MainActor
final class InputSourceSwitch {
    private var pending: (previous: String, selected: String)?

    func select(_ id: String?) {
        guard pending == nil, let id, let current = InputSource.currentID, current != id,
              InputSource.select(id) else { return }
        pending = (current, id)
    }

    func restore() {
        guard let pending else { return }
        self.pending = nil
        // A source the user picked by hand while the launcher was open is theirs to keep.
        guard InputSource.currentID == pending.selected else { return }
        InputSource.select(pending.previous)
    }
}
