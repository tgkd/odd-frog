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
    var model: any ModelCompleting
    var environment: [String: String]

    func run(_ step: WorkflowStep, values: WorkflowValues, workflowFile: URL,
             settings: [String: JSONValue]) async throws -> StepCompletion {
        switch step.kind {
        case .exec(let exec):
            return try await run(exec, values: values, workflowFile: workflowFile, settings: settings)
        case .show(let show):
            let text = try render(show.text, values)
            return StepCompletion(values: StepValues(output: text), note: text)
        case .llm(let llm):
            return try await run(llm, values: values, settings: settings)
        case .confirm:
            throw StepFailure("confirm steps are not available in this build yet.")
        }
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

    static let contextLimit = 256 * 1024
    static let jsonInstruction = "Answer with one JSON object and nothing else."

    private func run(_ step: LLMStep, values: WorkflowValues, settings: [String: JSONValue]) async throws -> StepCompletion {
        let text = try render(step.prompt, values)
        var sections: [String] = []
        for path in step.context {
            let content = try Self.readContext(path)
            sections.append("Context file \(path):\n\(content)")
        }
        if step.output == .json {
            sections.append(Self.jsonInstruction)
        }
        let prompt = ModelPrompt(provider: step.provider, model: step.model, system: sections.joined(separator: "\n\n"),
                                 prompt: text, json: step.output == .json)
        let reply: String
        do {
            reply = try await model.complete(prompt, settings: settings)
        } catch let error as CancellationError {
            throw error
        } catch let error as RPCError {
            throw StepFailure(error.message)
        } catch {
            throw StepFailure(String(describing: error))
        }
        try Task.checkCancellation()
        guard step.output == .json else {
            let output = Self.trimmingTrailing(reply)
            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StepFailure("The model returned no text.")
            }
            return StepCompletion(values: StepValues(output: output))
        }
        let cleaned = Self.removingFences(reply)
        guard !cleaned.isEmpty else {
            throw StepFailure("The model returned no text.")
        }
        guard let fields = try? JSONFields.parse(cleaned) else {
            throw StepFailure("The model did not return a JSON object.", detail: String(reply.prefix(Self.detailLimit)))
        }
        return StepCompletion(values: StepValues(output: cleaned, fields: fields))
    }

    static func readContext(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              size.isRegularFile == true else {
            throw StepFailure("Cannot read context file \(path).")
        }
        if let bytes = size.fileSize, bytes > contextLimit {
            throw StepFailure("Context file \(path) is larger than 256 KiB.")
        }
        guard let data = try? Data(contentsOf: url) else {
            throw StepFailure("Cannot read context file \(path).")
        }
        guard data.count <= contextLimit else {
            throw StepFailure("Context file \(path) is larger than 256 KiB.")
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw StepFailure("Cannot read context file \(path).")
        }
        return content
    }

    static func removingFences(_ reply: String) -> String {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: "\n").dropFirst()
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines = lines.dropLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
