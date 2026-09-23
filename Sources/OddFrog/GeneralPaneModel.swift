import Foundation
import Observation
import OddFrogCore
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

    @ObservationIgnored private var lastRecorded: Hotkey?
    @ObservationIgnored var onHotkey: ((Hotkey) -> Void)?

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

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
