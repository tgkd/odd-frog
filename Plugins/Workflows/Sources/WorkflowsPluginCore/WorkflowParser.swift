import Foundation
import OddFrogPluginAPI
import TOMLKit

public enum WorkflowParser {
    public static func parse(_ text: String, file: URL) throws -> Workflow {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: text)
        } catch let error as TOMLParseError {
            let position = error.source.begin
            let reason = error.description.trimmingCharacters(in: CharacterSet(charactersIn: ". \n"))
            throw failure("TOML syntax error at line \(position.line), column \(position.column): \(reason).")
        }
        let root = Fields(table: table)
        try root.rejectUnknown(allowed: ["id", "title", "keyword", "argument", "steps"])

        let id = try root.requiredString("id")
        guard id.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9_-]{0,63}/) != nil else {
            throw failure("Invalid id \"\(id)\". Use up to 64 letters, digits, \"_\" or \"-\", starting with a letter or digit.")
        }
        let title = try root.requiredString("title").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw failure("The title must not be empty.") }
        let keyword = try root.requiredString("keyword")
        guard keyword.wholeMatch(of: /[a-z][a-z0-9_-]*/) != nil else {
            throw failure("Invalid keyword \"\(keyword)\". Use lowercase letters, digits, \"_\" or \"-\", starting with a letter.")
        }
        let argument = try root.optionalTable("argument").map(parseArgument)
        let steps = try parseSteps(root)
        try checkReferences(steps)
        return Workflow(id: id, title: title, keyword: keyword, argument: argument, steps: steps, file: file)
    }

    private static func parseArgument(_ table: TOMLTable) throws -> PluginArgument {
        let fields = Fields(table: table, keyPrefix: "argument.")
        try fields.rejectUnknown(allowed: ["placeholder", "optional"])
        return PluginArgument(placeholder: try fields.optionalString("placeholder") ?? "Input",
                              optional: try fields.optionalBool("optional") ?? false)
    }

    private static func parseSteps(_ root: Fields) throws -> [WorkflowStep] {
        guard let value = root.table["steps"] else { throw failure("A workflow needs at least one [[steps]] entry.") }
        guard let array = value.array else { throw failure("Steps must be a list of [[steps]] tables.") }
        let tables = try array.map { element in
            guard let table = element.table else { throw failure("Steps must be a list of [[steps]] tables.") }
            return table
        }
        guard !tables.isEmpty else { throw failure("A workflow needs at least one [[steps]] entry.") }
        var seenIDs: Set<String> = []
        return try tables.enumerated().map { position, table in
            let step = try parseStep(table, position: position)
            if let id = step.id, !seenIDs.insert(id).inserted {
                throw failure("Step \"\(id)\": the id is used by an earlier step.")
            }
            return step
        }
    }

    private static let commonKeys: Set<String> = ["kind", "id", "on_error", "timeout"]
    private static let kindKeys: [String: Set<String>] = [
        "exec": ["argv", "cwd", "output"],
        "confirm": ["text", "title", "editable"],
        "show": ["text"],
    ]

    private static func parseStep(_ table: TOMLTable, position: Int) throws -> WorkflowStep {
        var fields = Fields(table: table, owner: "Step \(position + 1)")
        let id = try fields.optionalString("id")
        if let id {
            fields.owner = "Step \"\(id)\""
            guard id.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_-]*/) != nil else {
                throw fields.failure("invalid id. Use letters, digits, \"_\" or \"-\", starting with a letter or \"_\".")
            }
            guard id != "input" else { throw fields.failure("\"input\" is reserved for the typed text. Use another id.") }
        }
        let kind = try fields.requiredString("kind")
        guard let allowed = kindKeys[kind] else {
            throw fields.failure("unknown kind \"\(kind)\". Use exec, confirm or show.")
        }
        try rejectStepKeys(fields, kind: kind, allowed: allowed)

        let onError: WorkflowStep.OnError
        if let text = try fields.optionalString("on_error") {
            guard let value = WorkflowStep.OnError(rawValue: text) else {
                throw fields.failure("on_error must be \"stop\" or \"continue\".")
            }
            onError = value
        } else {
            onError = .stop
        }
        let timeout = try parseTimeout(fields)

        let stepKind: WorkflowStep.Kind
        switch kind {
        case "exec": stepKind = .exec(try parseExec(fields))
        case "confirm": stepKind = .confirm(try parseConfirm(fields))
        default: stepKind = .show(ShowStep(text: Template.parse(try fields.requiredString("text"))))
        }
        return WorkflowStep(id: id, position: position, kind: stepKind, onError: onError, timeout: timeout)
    }

    private static func rejectStepKeys(_ fields: Fields, kind: String, allowed: Set<String>) throws {
        for key in fields.table.keys.sorted() where !commonKeys.contains(key) && !allowed.contains(key) {
            if key == "max_chars" { throw fields.failure("max_chars is not available yet.") }
            if kindKeys.values.contains(where: { $0.contains(key) }) {
                throw fields.failure("\"\(key)\" is not a key of \(article(kind)) \(kind) step.")
            }
            throw fields.failure("unknown key \"\(key)\".")
        }
        if fields.table["timeout"] != nil, kind == "confirm" || kind == "show" {
            throw fields.failure("timeout is only for exec steps.")
        }
    }

    private static func article(_ kind: String) -> String {
        kind == "confirm" || kind == "show" ? "a" : "an"
    }

    private static func parseTimeout(_ fields: Fields) throws -> Duration? {
        guard let value = fields.table["timeout"] else { return nil }
        let seconds = value.int.map(Double.init) ?? value.double
        guard let seconds, seconds.isFinite, seconds > 0 else {
            throw fields.failure("timeout must be a positive number of seconds.")
        }
        return .milliseconds(Int(seconds * 1000))
    }

    private static func parseOutput(_ fields: Fields) throws -> StepOutput {
        guard let text = try fields.optionalString("output") else { return .text }
        guard let output = StepOutput(rawValue: text) else { throw fields.failure("output must be \"text\" or \"json\".") }
        return output
    }

    private static func parseExec(_ fields: Fields) throws -> ExecStep {
        let argv = try fields.requiredStringArray("argv")
        guard let command = argv.first else { throw fields.failure("argv must not be empty.") }
        guard !command.isEmpty else { throw fields.failure("argv[0] must not be empty.") }
        let templates = [Template.parse(expandingTilde(command))] + argv.dropFirst().map(Template.parse)
        let cwd = try fields.optionalString("cwd").map { Template.parse(expandingTilde($0)) }
        return ExecStep(argv: templates, cwd: cwd, output: try parseOutput(fields))
    }

    private static func parseConfirm(_ fields: Fields) throws -> ConfirmStep {
        ConfirmStep(text: Template.parse(try fields.requiredString("text")),
                    title: try fields.optionalString("title").map(Template.parse),
                    editable: try fields.optionalBool("editable") ?? true)
    }

    private static func expandingTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return ("~" as NSString).expandingTildeInPath + path.dropFirst()
    }

    private static let standardFields: [String: Set<String>] = [
        "exec": ["output", "last_line", "exit", "stderr"],
        "confirm": ["text", "title", "body", "file"],
    ]

    private static func checkReferences(_ steps: [WorkflowStep]) throws {
        var earlier: [String: WorkflowStep] = [:]
        for step in steps {
            for reference in templates(of: step).flatMap(\.references) {
                try check(reference, in: step, earlier: earlier)
            }
            if let id = step.id { earlier[id] = step }
        }
    }

    private static func check(_ reference: ValueReference, in step: WorkflowStep, earlier: [String: WorkflowStep]) throws {
        let owner = step.id.map { "Step \"\($0)\"" } ?? "Step \(step.position + 1)"
        func failure(_ reason: String) -> RPCError {
            WorkflowParser.failure("\(owner): \(reference.placeholder) — \(reason)")
        }
        if reference.name == "input" {
            guard reference.field == nil else { throw failure("input has no fields. Write {input}.") }
            return
        }
        guard let source = earlier[reference.name] else {
            throw failure("unknown step \"\(reference.name)\". Only earlier steps with an id can be used.")
        }
        guard let field = reference.field else {
            throw failure("write {\(reference.name).output} or another field.")
        }
        guard let allowed = standardFields[source.kindName] else {
            throw failure("a show step has no values.")
        }
        guard allowed.contains(field) || producesJSON(source) else {
            throw failure("unknown field \"\(field)\".")
        }
    }

    private static func producesJSON(_ step: WorkflowStep) -> Bool {
        switch step.kind {
        case .exec(let exec): exec.output == .json
        case .confirm, .show: false
        }
    }

    private static func templates(of step: WorkflowStep) -> [Template] {
        switch step.kind {
        case .exec(let exec): exec.argv + (exec.cwd.map { [$0] } ?? [])
        case .confirm(let confirm): [confirm.text] + (confirm.title.map { [$0] } ?? [])
        case .show(let show): [show.text]
        }
    }

    fileprivate static func failure(_ message: String) -> RPCError {
        RPCError("workflow", message)
    }
}

private struct Fields {
    let table: TOMLTable
    var owner = ""
    var keyPrefix = ""

    func failure(_ reason: String) -> RPCError {
        WorkflowParser.failure(owner.isEmpty ? capitalized(reason) : "\(owner): \(reason)")
    }

    private func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private func name(_ key: String) -> String {
        keyPrefix + key
    }

    func rejectUnknown(allowed: Set<String>) throws {
        if let key = table.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw failure("unknown key \"\(name(key))\".")
        }
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = try optionalString(key) else { throw failure("\(name(key)) is required.") }
        return value
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = table[key] else { return nil }
        guard let string = value.string else { throw failure("\(name(key)) must be a string.") }
        return string
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard let value = table[key] else { return nil }
        guard let bool = value.bool else { throw failure("\(name(key)) must be true or false.") }
        return bool
    }

    func optionalTable(_ key: String) throws -> TOMLTable? {
        guard let value = table[key] else { return nil }
        guard let table = value.table else { throw failure("\(name(key)) must be a table.") }
        return table
    }

    func requiredStringArray(_ key: String) throws -> [String] {
        guard let value = try optionalStringArray(key) else { throw failure("\(name(key)) is required.") }
        return value
    }

    func optionalStringArray(_ key: String) throws -> [String]? {
        guard let value = table[key] else { return nil }
        guard let array = value.array else { throw failure("\(name(key)) must be a list of strings.") }
        return try array.map { element in
            guard let string = element.string else { throw failure("\(name(key)) must be a list of strings.") }
            return string
        }
    }
}
