import Carbon
import Foundation
import OddFrogCore

@MainActor
final class HotKeyManager {
    enum RegistrationError: Error, CustomStringConvertible {
        case taken(Hotkey)
        case failed(Hotkey, OSStatus)

        var description: String {
            switch self {
            case .taken(let h): "\(h.description) is taken by another app"
            case .failed(let h, let status): "could not register \(h.description) (code \(status))"
            }
        }
    }

    private static let signature: OSType = 0x4F44_4446
    nonisolated(unsafe) private static weak var instance: HotKeyManager?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var activeID: UInt32 = 0
    private var nextID: UInt32 = 1
    private(set) var current: Hotkey?
    var onPress: (() -> Void)?

    init() {
        Self.instance = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == HotKeyManager.signature else { return OSStatus(eventNotHandledErr) }
            let id = hotKeyID.id
            Task { @MainActor in HotKeyManager.instance?.handlePress(id: id) }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    func apply(_ hotkey: Hotkey) throws {
        if hotkey == current { return }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            if status == OSStatus(eventHotKeyExistsErr) { throw RegistrationError.taken(hotkey) }
            throw RegistrationError.failed(hotkey, status)
        }
        if let old = hotKeyRef { UnregisterEventHotKey(old) }
        hotKeyRef = ref
        activeID = id
        current = hotkey
    }

    private func handlePress(id: UInt32) {
        guard id == activeID else { return }
        onPress?()
    }
}
