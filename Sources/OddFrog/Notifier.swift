import Foundation
import UserNotifications

@MainActor
final class Notifier {
    private let enabled = Bundle.main.bundleIdentifier != nil
    private var requested = false

    func requestAuthorizationIfNeeded() {
        guard enabled, !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, error in
            if let error { Log.write("notification authorization failed: \(error)") }
        }
    }

    func post(title: String, body: String, log: Bool = true) {
        if log { Log.write("notify: \(title) — \(body)") }
        guard enabled else { return }
        let deliver: @Sendable () -> Void = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error { Log.write("notification failed: \(error)") }
            }
        }
        if requested {
            deliver()
        } else {
            requested = true
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in deliver() }
        }
    }

    func failure(_ message: String) {
        post(title: "Odd Frog", body: message)
    }
}
