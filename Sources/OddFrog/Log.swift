import Foundation

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/odd-frog.log")
    private static let queue = DispatchQueue(label: "odd-frog.log")

    static func write(_ message: String) {
        NSLog("odd-frog: %@", message)
        let line = "\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
