import Foundation
import OddFrogPluginAPI

struct StepFailure: Error, Sendable {
    var summary: String
    var detail: String?
    var exit: Int?
    var stderr: String

    init(_ summary: String, detail: String? = nil, exit: Int? = nil, stderr: String = "") {
        self.summary = summary; self.detail = detail; self.exit = exit; self.stderr = stderr
    }

    static func joined(_ summary: String, detail: String?) -> String {
        guard let detail else { return summary }
        let head = summary.hasSuffix(".") ? String(summary.dropLast()) : summary
        return head + ": " + detail
    }
}

struct StepCompletion: Sendable {
    var values: StepValues
    var note: String?
}

struct StepExecutor: Sendable {
    static let detailLimit = 2000

    var exec: any ExecRunning
    var environment: [String: String]

    func run(_ step: WorkflowStep, values: WorkflowValues, workflowFile: URL,
             settings: [String: JSONValue]) async throws -> StepCompletion {
        switch step.kind {
        case .exec(let exec):
            return try await run(exec, values: values, workflowFile: workflowFile, settings: settings)
        case .show(let show):
            let text = try render(show.text, values)
            return StepCompletion(values: StepValues(output: text), note: text)
        case .confirm:
            throw StepFailure("A confirm step runs only through a review.")
        }
    }

    func review(_ step: ConfirmStep, values: WorkflowValues, workflowTitle: String) throws -> (title: String, text: String) {
        let text = try render(step.text, values)
        let rendered = try step.title.map { try render($0, values) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rendered.flatMap { $0.isEmpty ? nil : $0 } ?? workflowTitle
        return (title, text)
    }

    static func reviewed(_ text: String, _ parts: ReviewedText, file: URL) -> StepCompletion {
        let fields = ["text": text, "title": parts.title, "body": parts.body, "file": file.path]
        return StepCompletion(values: StepValues(output: text, fields: fields))
    }

    private func run(_ step: ExecStep, values: WorkflowValues, workflowFile: URL,
                     settings: [String: JSONValue]) async throws -> StepCompletion {
        let argv = try step.argv.map { try render($0, values) }
        guard let command = argv.first, !command.isEmpty else {
            throw StepFailure("The step has no command.")
        }
        let cwd: String
        if let template = step.cwd {
            cwd = try render(template, values)
            guard cwd.hasPrefix("/") else {
                throw StepFailure("cwd must be an absolute path.")
            }
        } else {
            cwd = workflowFile.deletingLastPathComponent().path
        }
        let path = CommandSearch.effectivePath(setting: settings["path"]?.string, appPath: environment["PATH"] ?? "")
        guard let executable = CommandSearch.resolve(command, cwd: cwd, path: path) else {
            throw StepFailure("Command not found: \(command)")
        }
        var environment = environment
        environment["PATH"] = path
        let result: ExecResult
        do {
            result = try await exec.run(ExecRequest(executable: executable, argv: argv,
                                                    cwd: cwd, environment: environment))
        } catch let error as CancellationError {
            throw error
        } catch {
            throw StepFailure(String(describing: error))
        }
        guard result.exit == 0 else {
            throw StepFailure("exited with code \(result.exit)", detail: Self.tail(result.stderr),
                              exit: result.exit, stderr: result.stderr)
        }
        var stepValues = StepValues(output: Self.trimmingTrailing(result.stdout), exit: result.exit, stderr: result.stderr)
        if step.output == .json {
            do {
                stepValues.fields = try JSONFields.parse(result.stdout)
            } catch {
                throw StepFailure(String(describing: error), exit: result.exit, stderr: result.stderr)
            }
        }
        return StepCompletion(values: stepValues)
    }

    private func render(_ template: Template, _ values: WorkflowValues) throws -> String {
        do {
            return try template.render(values)
        } catch {
            throw StepFailure(String(describing: error))
        }
    }

    static func trimmingTrailing(_ text: String) -> String {
        var text = Substring(text)
        while let last = text.last, last.isWhitespace || last.isNewline {
            text.removeLast()
        }
        return String(text)
    }

    static func tail(_ text: String) -> String? {
        let trimmed = trimmingTrailing(text)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.suffix(detailLimit))
    }
}
