import Foundation
import Testing
import OddFrogPluginAPI
import WorkflowsPluginCore

struct WorkflowParserTests {
    private let file = URL(fileURLWithPath: "/tmp/workflows/test.toml")
    private let header = """
    id = "test"
    title = "Test"
    keyword = "test"

    """
    private let home = NSHomeDirectory()

    private func parse(_ body: String) throws -> Workflow {
        try WorkflowParser.parse(header + body, file: file)
    }

    private func message(_ text: String) -> String? {
        do {
            _ = try WorkflowParser.parse(text, file: file)
            return nil
        } catch let error as RPCError {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    private func stepMessage(_ body: String) -> String? {
        message(header + body)
    }

    private let echo = """
    [[steps]]
    id = "run"
    kind = "exec"
    argv = ["/bin/echo", "{input}"]

    """

    @Test func parsesTheTargetWorkflow() throws {
        let text = #"""
        id = "idea"
        title = "New board task"
        keyword = "idea"
        argument = { placeholder = "Idea" }
        [[steps]]
        id = "draft"
        kind = "exec"
        argv = ["aigw", "-f", "~/.claude/skills/board/products.md", """
        Turn the idea into a board card for one of my products.
        Return {title, product, work_type, body}.
        Idea: {input}
        """]
        output = "json"
        [[steps]]
        id = "review"
        kind = "confirm"
        title = "{draft.product} · {draft.work_type}"
        text = "{draft.title}\n\n{draft.body}"
        editable = true
        [[steps]]
        id = "create"
        kind = "exec"
        argv = ["~/.claude/skills/board/scripts/board", "add", "{review.title}", "{review.file}",
                "Product={draft.product}", "Work Type={draft.work_type}", "Status=Inbox"]
        [[steps]]
        kind = "show"
        text = "Created: {create.last_line}"
        """#
        let workflow = try WorkflowParser.parse(text, file: file)
        #expect(workflow.id == "idea")
        #expect(workflow.title == "New board task")
        #expect(workflow.keyword == "idea")
        #expect(workflow.argument == PluginArgument(placeholder: "Idea", optional: false))
        #expect(workflow.file == file)
        #expect(workflow.steps.map(\.label) == ["draft", "review", "create", "step 4"])
        #expect(workflow.steps.map(\.position) == [0, 1, 2, 3])
        #expect(workflow.steps.allSatisfy { $0.onError == .stop && $0.timeout == nil })

        guard case .exec(let draft) = workflow.steps[0].kind else { Issue.record("draft is not exec"); return }
        #expect(draft.output == .json)
        #expect(draft.argv[2] == Template(parts: [.text("~/.claude/skills/board/products.md")]))
        #expect(draft.argv[3].references == [ValueReference(name: "input")])
        #expect(try draft.argv[3].render(WorkflowValues(input: "X")).contains("Return {title, product, work_type, body}."))

        guard case .confirm(let review) = workflow.steps[1].kind else { Issue.record("review is not confirm"); return }
        #expect(review.editable)
        #expect(review.title?.references == [ValueReference(name: "draft", field: "product"), ValueReference(name: "draft", field: "work_type")])

        guard case .exec(let create) = workflow.steps[2].kind else { Issue.record("create is not exec"); return }
        #expect(create.argv.count == 7)
        #expect(create.argv[0] == Template(parts: [.text(home + "/.claude/skills/board/scripts/board")]))
        #expect(create.cwd == nil)
        #expect(create.output == .text)

        guard case .show = workflow.steps[3].kind else { Issue.record("last step is not show"); return }
    }

    @Test func defaultsAndOptionalKeys() throws {
        let workflow = try parse("""
        argument = {}
        [[steps]]
        id = "run"
        kind = "exec"
        argv = ["echo"]
        cwd = "~/work"
        output = "json"
        on_error = "continue"
        timeout = 2.5
        [[steps]]
        kind = "exec"
        argv = ["/bin/echo", "p {run.anything}"]
        timeout = 30
        [[steps]]
        kind = "confirm"
        text = "t"
        editable = false
        """)
        #expect(workflow.argument == PluginArgument(placeholder: "Input", optional: false))
        #expect(workflow.steps[0].onError == .continue)
        #expect(workflow.steps[0].timeout == .milliseconds(2500))
        #expect(workflow.steps[1].timeout == .seconds(30))
        guard case .exec(let run) = workflow.steps[0].kind else { Issue.record("not exec"); return }
        #expect(run.cwd == Template(parts: [.text(home + "/work")]))
        guard case .exec(let second) = workflow.steps[1].kind else { Issue.record("not exec"); return }
        #expect(second.output == .text)
        guard case .confirm(let confirm) = workflow.steps[2].kind else { Issue.record("not confirm"); return }
        #expect(!confirm.editable)
        #expect(confirm.title == nil)
    }

    @Test func withoutArgumentTableThereIsNoArgument() throws {
        #expect(try parse(echo).argument == nil)
    }

    @Test func argumentKeysAreRead() throws {
        let workflow = try parse("argument = { placeholder = \"Name\", optional = true }\n" + echo)
        #expect(workflow.argument == PluginArgument(placeholder: "Name", optional: true))
    }

    @Test func tildeIsExpandedOnlyInArgvZeroAndCwd() throws {
        let workflow = try parse("""
        [[steps]]
        id = "run"
        kind = "exec"
        argv = ["~/bin/tool", "~/not-expanded", "~"]
        cwd = "~"
        """)
        guard case .exec(let run) = workflow.steps[0].kind else {
            Issue.record("wrong kind"); return
        }
        #expect(run.argv == [Template(parts: [.text(home + "/bin/tool")]), Template(parts: [.text("~/not-expanded")]), Template(parts: [.text("~")])])
        #expect(run.cwd == Template(parts: [.text(home)]))
    }

    @Test func tomlSyntaxErrorsNameLineAndColumn() throws {
        let text = try #require(message("id = \"x\"\ntitle = \n"))
        #expect(text.hasPrefix("TOML syntax error at line 2, column"))
    }

    @Test(arguments: [
        ("idx = \"x\"\n", "Unknown key \"idx\"."),
        ("argument = { placholder = \"x\" }\n", "Unknown key \"argument.placholder\"."),
        ("argument = \"x\"\n", "Argument must be a table."),
    ])
    func unknownTopLevelKeys(_ extra: String, _ expected: String) {
        #expect(message(header + extra + echo) == expected)
    }

    @Test(arguments: [
        ("title = \"T\"\nkeyword = \"k\"\n", "Id is required."),
        ("id = \"-bad\"\ntitle = \"T\"\nkeyword = \"k\"\n", "Invalid id \"-bad\". Use up to 64 letters, digits, \"_\" or \"-\", starting with a letter or digit."),
        ("id = \"\(String(repeating: "a", count: 65))\"\ntitle = \"T\"\nkeyword = \"k\"\n", nil),
        ("id = \"x\"\ntitle = \"  \"\nkeyword = \"k\"\n", "The title must not be empty."),
        ("id = \"x\"\ntitle = \"T\"\nkeyword = \"Idea\"\n", "Invalid keyword \"Idea\". Use lowercase letters, digits, \"_\" or \"-\", starting with a letter."),
        ("id = \"x\"\ntitle = 3\nkeyword = \"k\"\n", "Title must be a string."),
    ] as [(String, String?)])
    func topLevelValuesAreValidated(_ top: String, _ expected: String?) throws {
        let text = try #require(message(top + echo))
        if let expected { #expect(text == expected) } else { #expect(text.hasPrefix("Invalid id")) }
    }

    @Test func aWorkflowNeedsSteps() {
        #expect(message(header) == "A workflow needs at least one [[steps]] entry.")
        #expect(message(header + "steps = []\n") == "A workflow needs at least one [[steps]] entry.")
        #expect(message(header + "steps = 3\n") == "Steps must be a list of [[steps]] tables.")
    }

    @Test(arguments: [
        ("kind = \"exec\"\nargv = [\"a\"]\nargs = 1", "Step 1: unknown key \"args\"."),
        ("kind = \"confirm\"\ntext = \"t\"\nargv = [\"a\"]", "Step 1: \"argv\" is not a key of a confirm step."),
        ("kind = \"show\"\ntext = \"t\"\neditable = true", "Step 1: \"editable\" is not a key of a show step."),
        ("kind = \"exec\"\nargv = [\"a\"]\nmax_chars = 100", "Step 1: max_chars is not available yet."),
        ("kind = \"confirm\"\ntext = \"t\"\ntimeout = 5", "Step 1: timeout is only for exec steps."),
        ("kind = \"show\"\ntext = \"t\"\ntimeout = 5", "Step 1: timeout is only for exec steps."),
        ("kind = \"exec\"\nargv = [\"a\"]\ntimeout = 0", "Step 1: timeout must be a positive number of seconds."),
        ("kind = \"exec\"\nargv = [\"a\"]\ntimeout = \"5\"", "Step 1: timeout must be a positive number of seconds."),
        ("kind = \"exec\"\nargv = [\"a\"]\non_error = \"skip\"", "Step 1: on_error must be \"stop\" or \"continue\"."),
        ("kind = \"exec\"\nargv = [\"a\"]\noutput = \"yaml\"", "Step 1: output must be \"text\" or \"json\"."),
        ("kind = \"exec\"\nargv = []", "Step 1: argv must not be empty."),
        ("kind = \"exec\"\nargv = [1]", "Step 1: argv must be a list of strings."),
        ("kind = \"exec\"", "Step 1: argv is required."),
        ("argv = [\"a\"]", "Step 1: kind is required."),
        ("kind = \"run\"", "Step 1: unknown kind \"run\". Use exec, confirm or show."),
        ("kind = \"llm\"\nprompt = \"p\"", "Step 1: unknown kind \"llm\". Use exec, confirm or show."),
        ("kind = \"confirm\"\ntext = \"t\"\neditable = \"yes\"", "Step 1: editable must be true or false."),
        ("kind = \"show\"", "Step 1: text is required."),
        ("id = \"1st\"\nkind = \"show\"\ntext = \"t\"", "Step \"1st\": invalid id. Use letters, digits, \"_\" or \"-\", starting with a letter or \"_\"."),
        ("id = \"input\"\nkind = \"show\"\ntext = \"t\"", "Step \"input\": \"input\" is reserved for the typed text. Use another id."),
    ])
    func stepKeysAreValidated(_ step: String, _ expected: String) {
        #expect(stepMessage("[[steps]]\n" + step + "\n") == expected)
    }

    @Test func stepIDsAreUnique() {
        #expect(stepMessage(echo + echo) == "Step \"run\": the id is used by an earlier step.")
    }

    @Test(arguments: [
        ("{input.x}", "Step 2: {input.x} — input has no fields. Write {input}."),
        ("{run}", "Step 2: {run} — write {run.output} or another field."),
        ("{other}", "Step 2: {other} — unknown step \"other\". Only earlier steps with an id can be used."),
        ("{later.output}", "Step 2: {later.output} — unknown step \"later\". Only earlier steps with an id can be used."),
        ("{run.titel}", "Step 2: {run.titel} — unknown field \"titel\"."),
        ("{note.output}", "Step 2: {note.output} — a show step has no values."),
        ("{ask.output}", "Step 2: {ask.output} — unknown field \"output\"."),
    ])
    func referencesAreCheckedAtLoad(_ placeholder: String, _ expected: String) {
        let steps: String
        switch placeholder {
        case "{note.output}":
            steps = "[[steps]]\nid = \"note\"\nkind = \"show\"\ntext = \"x\"\n"
        case "{ask.output}":
            steps = "[[steps]]\nid = \"ask\"\nkind = \"confirm\"\ntext = \"x\"\n"
        default:
            steps = echo
        }
        let later = "[[steps]]\nid = \"later\"\nkind = \"show\"\ntext = \"x\"\n"
        #expect(stepMessage(steps + "[[steps]]\nkind = \"show\"\ntext = \"\(placeholder)\"\n" + later) == expected)
    }

    @Test func aStepCannotReferenceItself() {
        let body = "[[steps]]\nid = \"run\"\nkind = \"exec\"\nargv = [\"/bin/echo\", \"{run.output}\"]\n"
        #expect(stepMessage(body) == "Step \"run\": {run.output} — unknown step \"run\". Only earlier steps with an id can be used.")
    }

    @Test func referencesInEveryTemplateAreChecked() {
        let bodies = [
            "kind = \"exec\"\nargv = [\"a\"]\ncwd = \"{x.output}\"",
            "kind = \"confirm\"\ntext = \"t\"\ntitle = \"{x.output}\"",
            "kind = \"show\"\ntext = \"{x.output}\"",
        ]
        for body in bodies {
            #expect(stepMessage("[[steps]]\n" + body + "\n")?.contains("unknown step \"x\"") == true)
        }
    }

    @Test func allowedFieldsPerKind() throws {
        let workflow = try parse("""
        [[steps]]
        id = "run"
        kind = "exec"
        argv = ["a"]
        [[steps]]
        id = "data"
        kind = "exec"
        argv = ["a"]
        output = "json"
        [[steps]]
        id = "ask"
        kind = "confirm"
        text = "t"
        [[steps]]
        kind = "show"
        text = "{run.output}{run.last_line}{run.exit}{run.stderr}{data.anything}{data.output}{ask.text}{ask.title}{ask.body}{ask.file}{input}{{input.x}"
        """)
        #expect(workflow.steps.count == 4)
    }

    @Test func everyExampleWorkflowParses() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = repository.appendingPathComponent("examples/workflows")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "toml" }
        #expect(!files.isEmpty)
        for file in files {
            do {
                _ = try WorkflowParser.parse(String(contentsOf: file, encoding: .utf8), file: file)
            } catch {
                Issue.record("\(file.lastPathComponent): \(error)")
            }
        }
    }
}
