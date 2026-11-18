import Foundation
import Testing
import ClipboardPluginCore
import OddFrogPluginAPI

struct ClipboardProviderTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var now: Date { date("2026-09-09T12:00:00Z") }

    private func request(_ query: String = "", maxResults: Int = 50) -> PluginQuery {
        PluginQuery(query: query, fullQuery: "clip " + query, now: now,
                    timeZoneIdentifier: "UTC", maxResults: maxResults)
    }

    private func entry(_ id: String, _ text: String, copied: String = "2026-09-09T11:00:00Z") -> ClipboardEntry {
        ClipboardEntry(id: id, kind: .text, text: text, byteSize: text.utf8.count, hash: id, copied: date(copied))
    }

    private func imageEntry(_ id: String, width: Int = 200, height: Int = 100,
                            copied: String = "2026-09-09T11:00:00Z") -> ClipboardEntry {
        ClipboardEntry(id: id, kind: .image, width: width, height: height, byteSize: 10, hash: id, copied: date(copied))
    }

    @Test func setupAndDeniedReturnASingleAccessRow() {
        let setup = ClipboardProvider.respond(to: request(), access: .setup, entries: [], icons: [:], storage: nil, failure: nil)
        #expect(setup.map(\.id) == ["access"])
        #expect(setup[0].title == "Turn on clipboard history")
        #expect(setup[0].primary == PluginAction(.callback, "authorize", payload: .object([:])))
        #expect(setup[0].secondary == PluginAction(.openURL, "x-apple.systempreferences:com.apple.preference.security"))
        let denied = ClipboardProvider.respond(to: request(), access: .denied, entries: [], icons: [:], storage: nil, failure: nil)
        #expect(denied.map(\.id) == ["access"])
        #expect(denied[0].title == "Clipboard access is off")
        #expect(denied[0].primary == PluginAction(.openURL, "x-apple.systempreferences:com.apple.preference.security"))
    }

    @Test func emptyHistoryShowsTheEmptyRowWhenAllowed() {
        let items = ClipboardProvider.respond(to: request(), access: .allowed, entries: [], icons: [:], storage: nil, failure: nil)
        #expect(items.map(\.id) == ["empty"])
        #expect(items[0].title == "Clipboard history is empty")
        #expect(items[0].primary == nil)
    }

    @Test func failureReplacesTheEmptyRow() {
        let items = ClipboardProvider.respond(to: request(), access: .allowed, entries: [], icons: [:], storage: nil, failure: "boom")
        #expect(items.map(\.id) == ["failure"])
        #expect(items[0].title == "Clipboard history is not being saved")
        #expect(items[0].subtitle == "boom")
    }

    @Test func failureLeadsTheEntryRows() {
        let items = ClipboardProvider.respond(to: request(maxResults: 8), access: .allowed,
                                              entries: [entry("a", "Alpha")], icons: [:], storage: nil, failure: "boom")
        #expect(items.map(\.id) == ["failure", "a", "clear"])
        #expect(items[0].title == "Clipboard history is not being saved")
    }

    @Test func unfilteredListShowsTheFiveNewestEntries() {
        let many = (1...8).map { entry("e\($0)", "Entry \($0)") }
        let unfiltered = ClipboardProvider.respond(to: request(maxResults: 8), access: .allowed,
                                                   entries: many, icons: [:], storage: nil, failure: nil)
        #expect(unfiltered.map(\.id) == ["e1", "e2", "e3", "e4", "e5", "clear"])
        let filtered = ClipboardProvider.respond(to: request("entry", maxResults: 8), access: .allowed,
                                                 entries: many, icons: [:], storage: nil, failure: nil)
        #expect(filtered.count == 8)
    }

    @Test func clearRowAppearsOnlyWhenUnfilteredAndRoomExists() {
        let two = [entry("a", "Alpha"), entry("b", "Beta")]
        let unfiltered = ClipboardProvider.respond(to: request(maxResults: 8), access: .allowed,
                                                   entries: two, icons: [:], storage: nil, failure: nil)
        #expect(unfiltered.map(\.id) == ["a", "b", "clear"])
        #expect(unfiltered[2].title == "Clear clipboard history")
        #expect(unfiltered[2].primary == PluginAction(.callback, "clear", payload: .object([:])))
        let filtered = ClipboardProvider.respond(to: request("alpha", maxResults: 8), access: .allowed,
                                                 entries: two, icons: [:], storage: nil, failure: nil)
        #expect(filtered.map(\.id) == ["a"])
        let roomForClear = ClipboardProvider.respond(to: request(maxResults: 2), access: .allowed,
                                                     entries: two, icons: [:], storage: nil, failure: nil)
        #expect(roomForClear.map(\.id) == ["a", "clear"])
        let tight = ClipboardProvider.respond(to: request(maxResults: 1), access: .allowed,
                                              entries: two, icons: [:], storage: nil, failure: nil)
        #expect(tight.map(\.id) == ["a"])
    }

    @Test func filtersMatchTextAndImageTitles() {
        let entries = [entry("a", "Hello world"), imageEntry("b", width: 300, height: 200)]
        let text = ClipboardProvider.respond(to: request("HELLO", maxResults: 8), access: .allowed,
                                             entries: entries, icons: [:], storage: nil, failure: nil)
        #expect(text.map(\.id) == ["a"])
        let image = ClipboardProvider.respond(to: request("300", maxResults: 8), access: .allowed,
                                              entries: entries, icons: [:], storage: nil, failure: nil)
        #expect(image.map(\.id) == ["b"])
    }

    @Test func entryRowsCarryPasteDeleteAndThumbnail() {
        let items = ClipboardProvider.respond(to: request(maxResults: 8), access: .allowed,
                                              entries: [entry("a", "Alpha"), imageEntry("b")],
                                              icons: ["b": "/tmp/clip/images/b-thumb.png"], storage: nil, failure: nil)
        #expect(items[0].primary == PluginAction(.paste, "Alpha"))
        #expect(items[1].primary == PluginAction(.callback, "paste-image", payload: .object(["id": .string("b")])))
        #expect(items[0].secondary == PluginAction(.callback, "delete", payload: .object(["id": .string("a")])))
        #expect(items[0].symbol == "doc.on.clipboard")
        #expect(items[0].icon == nil)
        #expect(items[1].symbol == "photo")
        #expect(items[1].icon == "/tmp/clip/images/b-thumb.png")
    }

    @Test func dateLabelsNameTodayYesterdayAndOlderDays() {
        let entries = [entry("today", "t", copied: "2026-09-09T09:05:00Z"),
                       entry("yesterday", "y", copied: "2026-09-08T22:00:00Z"),
                       entry("older", "o", copied: "2026-09-01T08:00:00Z")]
        let items = ClipboardProvider.respond(to: request(), access: .allowed, entries: entries, icons: [:], storage: nil, failure: nil)
        #expect(items[0].subtitle?.hasPrefix("Today ") == true)
        #expect(items[1].subtitle?.hasPrefix("Yesterday ") == true)
        #expect(items[2].subtitle == "Tue 1 Sep")
    }

    @Test func titlesFallBackAndTruncate() {
        #expect(ClipboardEntry.title(for: entry("a", "  \n  Second line  \nbody")) == "Second line")
        #expect(ClipboardEntry.title(for: entry("b", "   \n\t  ")) == "")
        #expect(ClipboardEntry.title(for: entry("c", String(repeating: "x", count: 100))) == String(repeating: "x", count: 80))
        #expect(ClipboardEntry.title(for: imageEntry("d", width: 640, height: 480)) == "Image 640×480")
    }

    @Test func clearRowNamesWhereTheHistoryIsKept() {
        let memory = ClipboardProvider.respond(to: request(), access: .allowed, entries: [entry("a", "Alpha")],
                                               icons: [:], storage: nil, failure: nil)
        #expect(memory.last?.subtitle == "Removes 1 entries kept in memory only. What is on the clipboard now stays.")
        let file = ClipboardProvider.respond(to: request(), access: .allowed, entries: [entry("a", "Alpha")],
                                             icons: [:], storage: URL(fileURLWithPath: "/tmp/clip"), failure: nil)
        #expect(file.last?.subtitle == "Removes 1 entries saved unencrypted in /tmp/clip. What is on the clipboard now stays.")
    }
}
