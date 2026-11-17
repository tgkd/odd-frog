import Foundation
import OddFrogPluginAPI
import OddFrogHostServicesAPI

struct AppleNotesService: Sendable {
    private struct Written: Decodable { var title: String }

    func read(_ query: NotesQuery) async throws -> NotesSnapshot {
        let input: JSONValue = .object(["action": .string("read"), "query": .string(query.query),
                                        "limit": .number(Double(query.limit))])
        return try PluginProtocol.decoder().decode(NotesSnapshot.self, from: try await run(input))
    }

    func create(text: String) async throws -> String {
        let data = try await run(.object(["action": .string("create"), "text": .string(text)]))
        return try PluginProtocol.decoder().decode(Written.self, from: data).title
    }

    func append(_ request: NoteAppend) async throws -> String {
        let data = try await run(.object(["action": .string("append"), "id": .string(request.id), "text": .string(request.text)]))
        return try PluginProtocol.decoder().decode(Written.self, from: data).title
    }

    private func run(_ input: JSONValue) async throws -> Data {
        let argument = String(decoding: try PluginProtocol.encoder().encode(input), as: UTF8.self)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.script, argument]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let finished = AsyncStream<Int32> { continuation in
            process.terminationHandler = { continuation.yield($0.terminationStatus); continuation.finish() }
        }
        try process.run()
        let stdout = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let stderr = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(30))
            process.terminate()
        }
        let status = await withTaskCancellationHandler {
            var code: Int32 = -1
            for await value in finished { code = value }
            return code
        } onCancel: {
            process.terminate()
        }
        watchdog.cancel()
        try Task.checkCancellation()
        let data = await stdout.value
        let message = String(decoding: await stderr.value, as: UTF8.self)
        guard status == 0 else { throw Self.error(from: message, status: status) }
        return data
    }

    private static func error(from message: String, status: Int32) -> RPCError {
        if message.contains("-1743") {
            return RPCError("permission", "Allow Odd Frog to control Notes in System Settings › Privacy & Security › Automation.")
        }
        if status == 15 || status == -1 {
            return RPCError("notes", "Apple Notes did not answer in time.")
        }
        let line = message.split(whereSeparator: \.isNewline).last.map(String.init) ?? "Apple Notes failed."
        let cleaned = line.replacingOccurrences(of: #"^.*execution error: (Error: )*"#, with: "", options: .regularExpression)
        return RPCError("notes", cleaned.isEmpty ? "Apple Notes failed." : cleaned)
    }

    private static let script = #"""
    function run(argv) {
      const input = JSON.parse(argv[0]);
      const Notes = Application('Notes');
      const escape = line => line.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      const html = text => text.split('\n').map(line => '<div>' + (line.length ? escape(line) : '<br>') + '</div>').join('');
      const firstLine = text => (text.split('\n').find(line => line.trim().length) || 'Untitled').trim();
      const deleted = () => {
        const ids = new Set();
        const folders = Notes.folders.whose({name: 'Recently Deleted'});
        for (let i = 0; i < folders.length; i++) folders[i].notes.id().forEach(id => ids.add(id));
        return ids;
      };
      if (input.action === 'read') {
        const ref = input.query ? Notes.notes.whose({plaintext: {_contains: input.query}}) : Notes.notes;
        const ids = ref.id(), dates = ref.modificationDate(), locked = ref.passwordProtected();
        const skip = deleted();
        const rows = ids.map((id, i) => ({id, date: dates[i], locked: locked[i]}))
          .filter(row => !row.locked && !skip.has(row.id))
          .sort((a, b) => b.date - a.date);
        const notes = rows.slice(0, input.limit).map(row => ({
          id: row.id, text: Notes.notes.byId(row.id).plaintext(), modified: row.date.getTime() / 1000
        }));
        return JSON.stringify({notes, truncated: rows.length > input.limit});
      }
      if (input.action === 'create') {
        Notes.defaultAccount().defaultFolder().notes.push(Notes.Note({body: html(input.text)}));
        return JSON.stringify({title: firstLine(input.text)});
      }
      if (input.action === 'append') {
        const note = Notes.notes.byId(input.id);
        if (note.passwordProtected()) throw new Error('This note is locked.');
        note.body = note.body() + html(input.text);
        return JSON.stringify({title: firstLine(note.plaintext())});
      }
      throw new Error('Unknown Apple Notes action.');
    }
    """#
}
