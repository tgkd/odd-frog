import Foundation
import OddFrogPluginAPI

public enum NotesProvider {
    public static func respond(to request: PluginQuery, notes: [Note]) -> [PluginItem] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .gmt
        let filter = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = filter.isEmpty ? notes : notes.filter { $0.text.localizedStandardContains(filter) }
        let cap = max(1, min(request.maxResults, 50))
        let rows = matches.prefix(cap > 1 ? cap - 1 : 0).map { note in
            let details = [dateLabel(note.modified, calendar: calendar, now: request.now), Note.snippet(of: note.text)]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            return PluginItem(id: note.id, title: Note.title(of: note.text),
                              subtitle: details.joined(separator: " · "), kind: "Note", symbol: "note.text",
                              primary: PluginAction(.callback, "open", payload: .object(["id": .string(note.id)])))
        }
        return rows + [creation(filter)]
    }

    public static func view(for note: Note) -> PluginView {
        let empty = note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return PluginView(id: note.id, title: empty ? "New note" : Note.title(of: note.text), text: note.text,
                          placeholder: "Start writing…",
                          save: PluginAction(.callback, "save", payload: .object(["id": .string(note.id)])))
    }

    private static func creation(_ filter: String) -> PluginItem {
        guard !filter.isEmpty else {
            return PluginItem(id: "new", title: "New note", subtitle: "Press Return to start writing.",
                              kind: "Note", symbol: "plus.square",
                              primary: PluginAction(.callback, "create", payload: .object([:])))
        }
        return PluginItem(id: "new", title: "New note “\(filter)”",
                          subtitle: "Press Return to start a note with this text.",
                          kind: "Note", symbol: "plus.square",
                          primary: PluginAction(.callback, "create", payload: .object(["text": .string(filter)])))
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
