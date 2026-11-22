import Foundation
import OddFrogPluginAPI

public struct Workflow: Sendable, Equatable {
    public var id: String
    public var title: String
    public var keyword: String
    public var argument: PluginArgument?
    public var steps: [WorkflowStep]
    public var file: URL
    public init(id: String, title: String, keyword: String, argument: PluginArgument? = nil,
                steps: [WorkflowStep], file: URL) {
        self.id = id; self.title = title; self.keyword = keyword; self.argument = argument
        self.steps = steps; self.file = file
    }
}

public struct WorkflowStep: Sendable, Equatable {
    public enum OnError: String, Sendable { case stop, `continue` }
    public enum Kind: Sendable, Equatable {
        case exec(ExecStep)
        case confirm(ConfirmStep)
        case show(ShowStep)
    }
    public var id: String?
    public var position: Int
    public var kind: Kind
    public var onError: OnError
    public var timeout: Duration?
    public init(id: String? = nil, position: Int, kind: Kind, onError: OnError = .stop, timeout: Duration? = nil) {
        self.id = id; self.position = position; self.kind = kind; self.onError = onError; self.timeout = timeout
    }
    public var label: String { id ?? "step \(position + 1)" }
    public var kindName: String {
        switch kind {
        case .exec: "exec"
        case .confirm: "confirm"
        case .show: "show"
        }
    }
}

public enum StepOutput: String, Sendable { case text, json }

public struct ExecStep: Sendable, Equatable {
    public var argv: [Template]
    public var cwd: Template?
    public var output: StepOutput
    public init(argv: [Template], cwd: Template? = nil, output: StepOutput = .text) {
        self.argv = argv; self.cwd = cwd; self.output = output
    }
}

public struct ConfirmStep: Sendable, Equatable {
    public var text: Template
    public var title: Template?
    public var editable: Bool
    public init(text: Template, title: Template? = nil, editable: Bool = true) {
        self.text = text; self.title = title; self.editable = editable
    }
}

public struct ShowStep: Sendable, Equatable {
    public var text: Template
    public init(text: Template) { self.text = text }
}

public struct ValueReference: Sendable, Hashable {
    public var name: String
    public var field: String?
    public init(name: String, field: String? = nil) { self.name = name; self.field = field }
    public var placeholder: String { "{" + name + (field.map { "." + $0 } ?? "") + "}" }
}

public struct StepValues: Sendable, Equatable {
    public var output: String
    public var exit: Int?
    public var stderr: String
    public var fields: [String: String]
    public var failed: Bool
    public init(output: String = "", exit: Int? = nil, stderr: String = "", fields: [String: String] = [:], failed: Bool = false) {
        self.output = output; self.exit = exit; self.stderr = stderr; self.fields = fields; self.failed = failed
    }
}

public struct WorkflowValues: Sendable, Equatable {
    public var input: String
    public var steps: [String: StepValues]
    public init(input: String, steps: [String: StepValues] = [:]) { self.input = input; self.steps = steps }
}

public struct WorkflowFileError: Sendable, Equatable {
    public var file: URL
    public var message: String
    public init(file: URL, message: String) { self.file = file; self.message = message }
}
