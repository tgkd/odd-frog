import Foundation
import Observation
import OddFrogCore
import AppKit
import ServiceManagement

@Observable
@MainActor
final class GeneralPaneModel {
    private(set) var hotkey: Hotkey?
    private(set) var rejected: Hotkey?
    private(set) var hotkeyNote: String?
    private(set) var isRecording = false
    private(set) var loginStatus = LoginItem.status
    private(set) var loginError: String?
    private(set) var hasCustomPlacement = LauncherPlacement.saved != nil
    private(set) var notificationsOn = true
    private(set) var notificationsDenied = false
    private(set) var inputSource: String?
    private(set) var inputSources: [InputSource.Choice] = []

    @ObservationIgnored private var lastRecorded: Hotkey?
    @ObservationIgnored var onHotkey: ((Hotkey) -> Void)?
    @ObservationIgnored var onNotifications: ((Bool) -> Void)?
    @ObservationIgnored var onInputSource: ((String?) -> Void)?

    var recorderTitle: String {
        isRecording ? "Type shortcut…" : (rejected ?? hotkey)?.description ?? ""
    }

    var isLoginOn: Bool {
        loginStatus == .enabled || loginStatus == .requiresApproval
    }

    func show(_ hotkey: Hotkey, note: String?) {
        self.hotkey = hotkey
        if let note, !note.isEmpty {
            hotkeyNote = note
            rejected = lastRecorded
        } else {
            hotkeyNote = nil
            rejected = nil
        }
    }

    func record(_ hotkey: Hotkey) {
        lastRecorded = hotkey
        onHotkey?(hotkey)
    }

    func recordingChanged(_ recording: Bool) {
        isRecording = recording
        if recording {
            hotkeyNote = nil
            rejected = nil
        }
    }

    func refreshLogin() {
        withMutation(keyPath: \.loginStatus) { _loginStatus = LoginItem.status }
    }

    func refreshPlacement() {
        withMutation(keyPath: \.hasCustomPlacement) { _hasCustomPlacement = LauncherPlacement.saved != nil }
    }

    func resetPlacement() {
        LauncherPlacement.clear()
        refreshPlacement()
    }

    func toggleLogin() {
        loginError = nil
        do {
            try LoginItem.toggle()
        } catch {
            loginError = error.localizedDescription
        }
        refreshLogin()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated { self?.refreshLogin() }
        }
    }

    func showNotifications(_ on: Bool) {
        notificationsOn = on
    }

    func setNotifications(_ on: Bool) {
        notificationsOn = on
        onNotifications?(on)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.refreshNotificationAccess() }
        }
    }

    func refreshNotificationAccess() {
        Task { [weak self] in
            let denied = await Notifier.isDenied()
            self?.notificationsDenied = denied
        }
    }

    func showInputSource(_ id: String?) {
        inputSource = id
        refreshInputSources()
    }

    func refreshInputSources() {
        inputSources = InputSource.choices
    }

    func setInputSource(_ id: String?) {
        inputSource = id
        onInputSource?(id)
    }

    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
