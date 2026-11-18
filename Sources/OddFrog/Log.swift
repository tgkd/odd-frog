import Foundation
import OddFrogCore

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/odd-frog.log")
    private static let file = LogFile(url: url)
    private static let queue = DispatchQueue(label: "odd-frog.log")

    static func write(_ message: String) {
        NSLog("odd-frog: %@", message)
        let line = "\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))) \(message)\n"
        queue.async {
            file.append(line)
        }
    }
}
