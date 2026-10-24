import Carbon
import Foundation
import OddFrogCore

@MainActor
final class HotKeyManager {
    enum Slot: Hashable {
        case launcher
        case plugin(String)
    }

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

    private struct Registration {
        let hotkey: Hotkey
        let ref: EventHotKeyRef
        let id: UInt32
    }

    private static let signature: OSType = 0x4F44_4446
    nonisolated(unsafe) private static weak var instance: HotKeyManager?

    private var handlerRef: EventHandlerRef?
    private var registrations: [Slot: Registration] = [:]
    private var nextID: UInt32 = 1
    var current: Hotkey? { registrations[.launcher]?.hotkey }
    var onPress: ((Slot) -> Void)?

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

    func hotkey(for slot: Slot) -> Hotkey? {
        registrations[slot]?.hotkey
    }

    var pluginIDs: [String] {
        registrations.keys.compactMap { if case .plugin(let id) = $0 { id } else { nil } }
    }

    func apply(_ hotkey: Hotkey) throws {
        try apply(hotkey, for: .launcher)
    }

    func apply(_ hotkey: Hotkey?, for slot: Slot) throws {
        if hotkey == registrations[slot]?.hotkey { return }
        guard let hotkey else {
            if let old = registrations.removeValue(forKey: slot) { UnregisterEventHotKey(old.ref) }
            return
        }
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
        if let old = registrations[slot] { UnregisterEventHotKey(old.ref) }
        registrations[slot] = Registration(hotkey: hotkey, ref: ref, id: id)
    }

    private func handlePress(id: UInt32) {
        guard let slot = registrations.first(where: { $0.value.id == id })?.key else { return }
        onPress?(slot)
    }
}
