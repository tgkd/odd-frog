import Foundation
import Testing
import WorkflowsPluginCore

struct WorkflowLibraryTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkflowLibraryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ name: String, in folder: URL, id: String, keyword: String? = nil) throws -> URL {
        let text = """
        id = "\(id)"
        title = "Title \(id)"
        keyword = "\(keyword ?? id)"
        [[steps]]
        kind = "show"
        text = "{input}"
        """
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func scansFoldersInOrderAndFilesByName() throws {
        let first = try folder("first")
        let second = try folder("second")
        try write("b.toml", in: first, id: "b")
        try write("a.TOML", in: first, id: "a")
        try write("c.toml", in: second, id: "c")
        try write("notes.txt", in: first, id: "txt")
        try write(".hidden.toml", in: first, id: "hidden")
        let nested = try folder("first/nested")
        try write("deep.toml", in: nested, id: "deep")

        let library = WorkflowLibrary.scan(folders: [second, first])
        #expect(library.workflows.map(\.id) == ["c", "a", "b"])
        #expect(library.errors.isEmpty)
        #expect(library.workflows.first?.file.lastPathComponent == "c.toml")
    }

    @Test func missingFolderGivesOneError() throws {
        let missing = root.appendingPathComponent("missing")
        let present = try folder("present")
        try write("a.toml", in: present, id: "a")
        let library = WorkflowLibrary.scan(folders: [missing, present])
        #expect(library.errors == [WorkflowFileError(file: missing, message: "Folder not found.")])
        #expect(library.workflows.map(\.id) == ["a"])
    }

    @Test func aFileIsNotAFolder() throws {
        let file = try write("a.toml", in: root, id: "a")
        #expect(WorkflowLibrary.scan(folders: [file]).errors == [WorkflowFileError(file: file, message: "Folder not found.")])
    }

    @Test func parseErrorsAreEntriesWithTheParserMessage() throws {
        let folder = try folder("broken")
        let bad = folder.appendingPathComponent("bad.toml")
        try "id = \"x\"\ntitle = \n".write(to: bad, atomically: true, encoding: .utf8)
        let invalid = folder.appendingPathComponent("invalid.toml")
        try "id = \"x\"\ntitle = \"T\"\nkeyword = \"x\"\n".write(to: invalid, atomically: true, encoding: .utf8)
        try write("ok.toml", in: folder, id: "ok")

        let library = WorkflowLibrary.scan(folders: [folder])
        #expect(library.workflows.map(\.id) == ["ok"])
        #expect(library.errors.map(\.file.lastPathComponent) == [bad.lastPathComponent, invalid.lastPathComponent])
        #expect(library.errors[0].message.hasPrefix("TOML syntax error at line 2, column"))
        #expect(library.errors[1].message == "A workflow needs at least one [[steps]] entry.")
    }

    @Test func symlinkedFilesAreReadOnce() throws {
        let first = try folder("one")
        let second = try folder("two")
        let original = try write("a.toml", in: first, id: "a")
        try FileManager.default.createSymbolicLink(at: second.appendingPathComponent("link.toml"), withDestinationURL: original)
        try FileManager.default.createSymbolicLink(at: first.appendingPathComponent("z.toml"), withDestinationURL: original)

        let library = WorkflowLibrary.scan(folders: [first, second, first])
        #expect(library.workflows.map(\.id) == ["a"])
        #expect(library.errors.isEmpty)
    }

    @Test func clashingIDAndKeywordLoseToTheEarlierFile() throws {
        let first = try folder("early")
        let second = try folder("late")
        try write("one.toml", in: first, id: "one", keyword: "go")
        try write("two.toml", in: second, id: "one", keyword: "two")
        let keywordClash = try write("three.toml", in: second, id: "three", keyword: "go")

        let library = WorkflowLibrary.scan(folders: [first, second])
        #expect(library.workflows.map(\.file.lastPathComponent) == ["one.toml"])
        #expect(library.errors.map(\.message) == [
            "The keyword \"go\" is already used by one.toml.",
            "The id \"one\" is already used by one.toml.",
        ])
        #expect(library.errors.first?.file.lastPathComponent == keywordClash.lastPathComponent)
    }
}
