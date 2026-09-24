import Foundation
import OddFrogPluginAPI

public enum ClipboardProvider {
    public enum Access: Sendable {
        case allowed
        case setup
        case denied
    }

    public static func respond(to request: PluginQuery, access: Access, entries: [ClipboardEntry],
                               directory: URL, failure: String?) -> [PluginItem] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .gmt
        switch access {
        case .setup:
            return [PluginItem(id: "access", title: "Turn on clipboard history",
                               subtitle: "Copy some text in another app, then press Return here.",
                               kind: "Clipboard", symbol: "doc.on.clipboard",
                               primary: PluginAction(.callback, "authorize", payload: .object([:])),
                               secondary: PluginAction(.openURL, "x-apple.systempreferences:com.apple.preference.security"))]
        case .denied:
            return [PluginItem(id: "access", title: "Clipboard access is off",
                               subtitle: "Press Return to open Privacy & Security and choose Always Allow for Odd Frog.",
                               kind: "Clipboard", symbol: "doc.on.clipboard",
                               primary: PluginAction(.openURL, "x-apple.systempreferences:com.apple.preference.security"))]
        case .allowed:
            break
        }
        if entries.isEmpty {
            if let failure {
                return [failureRow(failure)]
            }
            return [PluginItem(id: "empty", title: "Clipboard history is empty",
                               subtitle: "Copied text and images will appear here.",
                               kind: "Clipboard", symbol: "doc.on.clipboard")]
        }
        let filter = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = filter.isEmpty ? entries : entries.filter {
            switch $0.kind {
            case .text:
                return ($0.text ?? "").localizedStandardContains(filter)
            case .image:
                return ClipboardEntry.title(for: $0).localizedStandardContains(filter)
            }
        }
        let cap = max(1, min(request.maxResults, 50))
        var rows: [PluginItem] = []
        if let failure {
            rows.append(failureRow(failure))
        }
        let available = max(0, cap - rows.count)
        guard available > 0 else {
            return rows
        }
        if filter.isEmpty && available > 1 {
            let limited = Array(matches.prefix(available - 1))
            rows += limited.map { entryRow($0, now: request.now, calendar: calendar, directory: directory) }
            rows.append(clearRow(count: entries.count))
        } else {
            rows += matches.prefix(available).map { entryRow($0, now: request.now, calendar: calendar, directory: directory) }
        }
        return rows
    }

    private static func failureRow(_ failure: String) -> PluginItem {
        PluginItem(id: "failure", title: "Clipboard history is not being saved",
                   subtitle: failure, kind: "Clipboard", symbol: "exclamationmark.triangle")
    }

    private static func entryRow(_ entry: ClipboardEntry, now: Date, calendar: Calendar, directory: URL) -> PluginItem {
        let isImage = entry.kind == .image
        return PluginItem(id: entry.id, title: ClipboardEntry.title(for: entry),
                          subtitle: dateLabel(entry.copied, calendar: calendar, now: now),
                          kind: "Clipboard",
                          symbol: isImage ? "photo" : "doc.on.clipboard",
                          icon: isImage ? ClipboardArchive.thumbnailPath(in: directory, id: entry.id) : nil,
                          primary: PluginAction(.callback, "copy", payload: .object(["id": .string(entry.id)])),
                          secondary: PluginAction(.callback, "delete", payload: .object(["id": .string(entry.id)])))
    }

    private static func clearRow(count: Int) -> PluginItem {
        PluginItem(id: "clear", title: "Clear clipboard history",
                   subtitle: "Removes \(count) saved entries. What is on the clipboard now stays.",
                   kind: "Clipboard", symbol: "trash",
                   primary: PluginAction(.callback, "clear", payload: .object([:])))
    }

    private static func dateLabel(_ modified: Date, calendar: Calendar, now: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: modified),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days == 0 || days == 1 {
            let time = DateFormatter()
            time.timeZone = calendar.timeZone
            time.dateStyle = .none
            time.timeStyle = .short
            return "\(days == 0 ? "Today" : "Yesterday") \(time.string(from: modified))"
        }
        let date = DateFormatter()
        date.timeZone = calendar.timeZone
        date.dateFormat = "EEE d MMM"
        return date.string(from: modified)
    }
}
