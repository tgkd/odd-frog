import Foundation
import Testing
import NotesPluginCore
import OddFrogPluginAPI

struct NotesProviderTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var now: Date { date("2026-09-09T12:00:00Z") }

    private func request(_ query: String = "", maxResults: Int = 50) -> PluginQuery {
        PluginQuery(query: query, fullQuery: "note " + query, now: now,
                    timeZoneIdentifier: "UTC", maxResults: maxResults)
    }

    private func note(_ id: String, _ text: String, modified: String = "2026-09-09T11:00:00Z") -> Note {
        Note(id: id, text: text, modified: date(modified))
    }

    @Test func emptyQueryListsEveryNoteAndEndsWithTheCreationRow() {
        let items = NotesProvider.respond(to: request(), notes: [note("a", "Alpha"), note("b", "Beta")])
        #expect(items.map(\.id) == ["a", "b", "new"])
        #expect(items[0].title == "Alpha")
        #expect(items[0].kind == "Note")
        #expect(items[0].symbol == "note.text")
        #expect(items[0].primary == PluginAction(.callback, "open", payload: .object(["id": .string("a")])))
        #expect(items[0].secondary == nil)
        #expect(items[0].history == nil)
        #expect(items[2].title == "New note")
        #expect(items[2].subtitle == "Press Return to start writing.")
        #expect(items[2].symbol == "plus.square")
        #expect(items[2].primary == PluginAction(.callback, "create", payload: .object([:])))
    }

    @Test func filtersMatchTitleAndBodyCaseInsensitively() {
        let notes = [note("groceries", "Groceries\nmilk and eggs"), note("meeting", "Meeting notes\nbudget review")]
        #expect(NotesProvider.respond(to: request("MILK"), notes: notes).map(\.id) == ["groceries", "new"])
        #expect(NotesProvider.respond(to: request("meeting"), notes: notes).map(\.id) == ["meeting", "new"])
        #expect(NotesProvider.respond(to: request("zzz"), notes: notes).map(\.id) == ["new"])
        let items = NotesProvider.respond(to: request("  milk  "), notes: notes)
        #expect(items[1].title == "New note “milk”")
        #expect(items[1].subtitle == "Press Return to start a note with this text.")
        #expect(items[1].primary == PluginAction(.callback, "create", payload: .object(["text": .string("milk")])))
    }

    @Test func capsAlwaysLeaveRoomForTheCreationRow() {
        let five = (0..<5).map { note("n\($0)", "Note \($0)") }
        #expect(NotesProvider.respond(to: request(maxResults: 3), notes: five).map(\.id) == ["n0", "n1", "new"])
        #expect(NotesProvider.respond(to: request(maxResults: 1), notes: five).map(\.id) == ["new"])
        let many = (0..<60).map { note("n\($0)", "Note \($0)") }
        let items = NotesProvider.respond(to: request(maxResults: 50), notes: many)
        #expect(items.count == 50)
        #expect(items.dropLast().map(\.id) == (0..<49).map { "n\($0)" })
        #expect(items.last?.id == "new")
    }

    @Test func titlesFallBackAndTruncate() {
        #expect(Note.title(of: "   \n\t  \n") == "Untitled")
        #expect(Note.title(of: "") == "Untitled")
        #expect(Note.title(of: "\n\n  Second line title  \nbody") == "Second line title")
        #expect(Note.title(of: String(repeating: "x", count: 100)) == String(repeating: "x", count: 80))
        #expect(NotesProvider.respond(to: request(), notes: [note("a", "  \n ")])[0].title == "Untitled")
    }

    @Test func snippetsUseTheSecondNonEmptyLine() {
        #expect(Note.snippet(of: "Title\n\n\n  Body line  ") == "Body line")
        #expect(Note.snippet(of: "Only line") == nil)
        #expect(Note.snippet(of: "") == nil)
        #expect(Note.snippet(of: "Title\n" + String(repeating: "y", count: 100)) == String(repeating: "y", count: 80))
        let items = NotesProvider.respond(to: request(), notes: [note("a", "Title\nBody")])
        #expect(items[0].subtitle?.hasSuffix(" · Body") == true)
    }

    @Test func dateLabelsNameTodayYesterdayAndOlderDays() {
        let notes = [note("today", "Today note", modified: "2026-09-09T09:05:00Z"),
                     note("yesterday", "Yesterday note", modified: "2026-09-08T22:00:00Z"),
                     note("older", "Older note", modified: "2026-09-01T08:00:00Z")]
        let items = NotesProvider.respond(to: request(), notes: notes)
        #expect(items[0].subtitle?.hasPrefix("Today ") == true)
        #expect(items[1].subtitle?.hasPrefix("Yesterday ") == true)
        #expect(items[2].subtitle == "Tue 1 Sep")
    }

    @Test func viewCarriesASaveCallbackForTheNote() {
        let view = NotesProvider.view(for: note("a", "Meeting notes\nbudget review"))
        #expect(view.kind == .editor)
        #expect(view.id == "a")
        #expect(view.title == "Meeting notes")
        #expect(view.text == "Meeting notes\nbudget review")
        #expect(view.placeholder == "Start writing…")
        #expect(view.save == PluginAction(.callback, "save", payload: .object(["id": .string("a")])))
        #expect(NotesProvider.view(for: note("b", "")).title == "New note")
        #expect(NotesProvider.view(for: note("c", "  \n ")).title == "New note")
    }

    @Test func effectsWithAViewRoundTrip() throws {
        let effects = PluginEffects(refreshQuery: true, view: NotesProvider.view(for: note("a", "Alpha\nbody")))
        let decoded = try JSONValue.encode(effects).decode(PluginEffects.self)
        #expect(decoded.refreshQuery)
        #expect(decoded.view == effects.view)
        let items = NotesProvider.respond(to: request(), notes: [note("a", "Alpha\nbody")])
        #expect(try JSONValue.encode(items).decode([PluginItem].self) == items)
    }
}
