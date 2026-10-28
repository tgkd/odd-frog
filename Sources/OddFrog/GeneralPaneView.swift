import SwiftUI
import ServiceManagement

struct GeneralPaneView: View {
    let model: GeneralPaneModel

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HotkeyRecorderView(
                        title: model.recorderTitle,
                        onRecord: { model.record($0) },
                        onRecordingChanged: { model.recordingChanged($0) }
                    )
                    .fixedSize()
                } label: {
                    Text("Keyboard shortcut")
                    shortcutHelper
                }

                Toggle(isOn: Binding(get: { model.isLoginOn }, set: { _ in model.toggleLogin() })) {
                    Text("Launch at login")
                    loginHelper
                }
                .disabled(model.loginStatus == .notFound)

                if model.loginStatus == .requiresApproval {
                    Button("Open Login Items…") { model.openLoginItems() }
                }

                Toggle(isOn: Binding(get: { model.notificationsOn }, set: { model.setNotifications($0) })) {
                    Text("Notifications")
                    notificationsHelper
                }

                if model.notificationsOn && model.notificationsDenied {
                    Button("Open Notification Settings…") { model.openNotificationSettings() }
                }

                LabeledContent {
                    Button("Reset") { model.resetPlacement() }
                        .disabled(!model.hasCustomPlacement)
                } label: {
                    Text("Launcher position")
                    placementHelper
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var shortcutHelper: some View {
        if model.isRecording {
            Text("Press the keys you want to use.")
        } else if let note = model.hotkeyNote {
            Text(note + " Try another combination.")
                .foregroundStyle(.red)
        } else {
            Text("Click, then press a new combination.")
        }
    }

    @ViewBuilder
    private var loginHelper: some View {
        if let error = model.loginError {
            Text(error).foregroundStyle(.red)
        } else {
            switch model.loginStatus {
            case .enabled:
                Text("Odd Frog opens when you log in.")
            case .requiresApproval:
                Text("Waiting for approval in System Settings › Login Items.")
                    .foregroundStyle(.orange)
            case .notFound:
                Text("Move Odd Frog to your Applications folder to enable this.")
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var notificationsHelper: some View {
        if model.notificationsOn && model.notificationsDenied {
            Text("macOS blocks Odd Frog notifications. Allow them in System Settings › Notifications.")
                .foregroundStyle(.orange)
        } else {
            Text("Script output, plugin messages and failures. Scripts can also post with odd-frog://notify?title=…&body=….")
        }
    }

    @ViewBuilder
    private var placementHelper: some View {
        if model.hasCustomPlacement {
            Text("Opens where you last dragged it.")
        } else {
            Text("Opens on the screen with the pointer. Drag the launcher by its edge to keep it in one place.")
        }
    }
}
