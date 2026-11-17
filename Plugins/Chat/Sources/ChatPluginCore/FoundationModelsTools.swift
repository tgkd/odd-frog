import Foundation
import FoundationModels

typealias ActivityReport = @Sendable (String) -> Void

enum FoundationModelsTools {
    static func all(_ actions: ChatActions, report: @escaping ActivityReport) -> [any Tool] {
        [CalendarEventsTool(actions: actions, report: report), CreateEventTool(actions: actions, report: report),
         RemindersTool(actions: actions, report: report), AddReminderTool(actions: actions, report: report),
         CompleteReminderTool(actions: actions, report: report), NotesTool(actions: actions, report: report),
         CreateNoteTool(actions: actions, report: report), AppendNoteTool(actions: actions, report: report)]
    }

    static func deliver(_ outcome: ChatOutcome, _ report: ActivityReport) -> String {
        if let activity = outcome.activity {
            report(activity)
        }
        return outcome.reply
    }
}

struct CalendarEventsTool: Tool {
    let name = "calendar_events"
    let description = "List the user's calendar events for some days."
    let actions: ChatActions
    let report: ActivityReport

    @Generable
    struct Arguments {
        @Guide(description: "First day, YYYY-MM-DD. Empty means today.")
        var from: String?
        @Guide(description: "How many days to list, 1 to 31.")
        var days: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        FoundationModelsTools.deliver(await actions.events(from: arguments.from, days: arguments.days), report)
    }
}

struct CreateEventTool: Tool {
    let name = "create_event"
    let description = "Add an event to the user's default calendar."
    let actions: ChatActions
    let report: ActivityReport

    @Generable
    struct Arguments {
        @Guide(description: "Event title.")
        var title: String
        @Guide(description: "Day, YYYY-MM-DD.")
        var date: String
        @Guide(description: "Start time, HH:MM 24-hour. Empty for an all-day event.")
        var time: String?
        @Guide(description: "Optional last day, YYYY-MM-DD, for events over several days.")
        var endDate: String?
        @Guide(description: "Optional end time, HH:MM. Default: one hour after the start.")
        var endTime: String?
        @Guide(description: "Optional place.")
        var location: String?
    }

    func call(arguments: Arguments) async throws -> String {
        FoundationModelsTools.deliver(await actions.createEvent(
            title: arguments.title, date: arguments.date, time: arguments.time, endDate: arguments.endDate,
            endTime: arguments.endTime, location: arguments.location), report)
    }
}

struct RemindersTool: Tool {
    let name = "reminders"
    let description = "List the user's open reminders."
    let actions: ChatActions
    let report: ActivityReport

    @Generable
    struct Arguments {
        @Guide(description: "Optional words to find in reminder titles.")
        var search: String?
    }

    func call(arguments: Arguments) async throws -> String {
        FoundationModelsTools.deliver(await actions.reminders(search: arguments.search), report)
    }
}

struct AddReminderTool: Tool {
    let name = "add_reminder"
    let description = "Add a reminder to the user's default Reminders list."
    let actions: ChatActions
    let report: ActivityReport

    @Generable
    struct Arguments {
        @Guide(description: "What to remind about.")
        var title: String
        @Guide(description: "Optional due day, YYYY-MM-DD.")
        var date: String?
        @Guide(description: "Optional due time, HH:MM 24-hour. Always set it when the user names a time.")
        var time: String?
    }

    func call(arguments: Arguments) async throws -> String {
        FoundationModelsTools.deliver(await actions.addReminder(
            title: arguments.title, date: arguments.date, time: arguments.time), report)
    }
}

struct CompleteReminderTool: Tool {
    let name = "complete_reminder"
    let description = "Mark one open reminder as done, found by its title."
    let actions: ChatActions
    let report: ActivityReport

    @Generable
    struct Arguments {
        @Guide(description: "The reminder title or words from it.")
        var title: String
    }

    func call(arguments: Arguments) async throws -> String {
        FoundationModelsTools.deliver(await actions.completeReminder(title: arguments.title), report)
    }
}

struct NotesTool: Tool {
    let name = "search_notes"
    let description = "Read the user's notes, newest first."
    let actions: ChatActions
    let report: ActivityReport

    @Generable
    struct Arguments {
        @Guide(description: "Optional words to find in notes.")
        var search: String?
    }

    func call(arguments: Arguments) async throws -> String {
        FoundationModelsTools.deliver(await actions.notes(search: arguments.search), report)
    }
}

struct CreateNoteTool: Tool {
    let name = "create_note"
    let description = "Write a new note. The first line is its title."
    let actions: ChatActions
    let report: ActivityReport

    @Generable
    struct Arguments {
        @Guide(description: "The full note text.")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        FoundationModelsTools.deliver(await actions.createNote(text: arguments.text), report)
    }
}

struct AppendNoteTool: Tool {
    let name = "append_to_note"
    let description = "Add text to the end of an existing note, found by its title."
    let actions: ChatActions
    let report: ActivityReport

    @Generable
    struct Arguments {
        @Guide(description: "The note title or words from it.")
        var title: String
        @Guide(description: "Text to add.")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        FoundationModelsTools.deliver(await actions.appendToNote(title: arguments.title, text: arguments.text), report)
    }
}
