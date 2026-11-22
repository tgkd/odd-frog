import Foundation
import OddFrogPluginAPI

public struct Template: Sendable, Equatable {
    public enum Part: Sendable, Equatable {
        case text(String)
        case value(ValueReference)
    }
    public var parts: [Part]
    public init(parts: [Part]) { self.parts = parts }

    public static func parse(_ source: String) -> Template {
        Template(parts: [.text(source)])
    }

    public var references: [ValueReference] {
        parts.compactMap { part in
            if case .value(let reference) = part { reference } else { nil }
        }
    }

    public func render(_ values: WorkflowValues) throws -> String {
        try parts.map { part in
            switch part {
            case .text(let text): text
            case .value(let reference): try values.resolve(reference)
            }
        }.joined()
    }
}

public extension WorkflowValues {
    func resolve(_ reference: ValueReference) throws -> String {
        if reference.name == "input", reference.field == nil {
            return input
        }
        guard let step = steps[reference.name], let field = reference.field else {
            throw RPCError("workflow", "\(reference.placeholder) has no value.")
        }
        switch field {
        case "output": return step.output
        case "exit": return step.exit.map(String.init) ?? ""
        case "stderr": return step.stderr
        default:
            guard let value = step.fields[field] else {
                throw RPCError("workflow", "\(reference.placeholder) has no value.")
            }
            return value
        }
    }
}

public enum JSONFields {
    public static func parse(_ text: String) throws -> [String: String] {
        throw RPCError("workflow", "JSON fields are not built yet.")
    }
}
