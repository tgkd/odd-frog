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
        var parts: [Part] = []
        var literal = ""
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            guard character == "{" else {
                literal.append(character)
                index = next
                continue
            }
            if next < source.endIndex, source[next] == "{" {
                literal.append("{")
                index = source.index(after: next)
                continue
            }
            guard let (reference, end) = placeholder(in: source, after: next) else {
                literal.append("{")
                index = next
                continue
            }
            if !literal.isEmpty { parts.append(.text(literal)) }
            literal = ""
            parts.append(.value(reference))
            index = end
        }
        if !literal.isEmpty { parts.append(.text(literal)) }
        return Template(parts: parts)
    }

    private static func placeholder(in source: String, after start: String.Index) -> (ValueReference, String.Index)? {
        guard let (name, afterName) = identifier(in: source, from: start), afterName < source.endIndex else { return nil }
        if source[afterName] == "}" {
            return (ValueReference(name: name), source.index(after: afterName))
        }
        guard source[afterName] == "." else { return nil }
        let fieldStart = source.index(after: afterName)
        guard let (field, afterField) = identifier(in: source, from: fieldStart), afterField < source.endIndex,
              source[afterField] == "}" else { return nil }
        return (ValueReference(name: name, field: field), source.index(after: afterField))
    }

    private static func identifier(in source: String, from start: String.Index) -> (String, String.Index)? {
        guard start < source.endIndex, isIdentifierHead(source[start]) else { return nil }
        var end = source.index(after: start)
        while end < source.endIndex, isIdentifierBody(source[end]) {
            end = source.index(after: end)
        }
        return (String(source[start..<end]), end)
    }

    private static func isIdentifierHead(_ character: Character) -> Bool {
        character == "_" || (character.isASCII && character.isLetter)
    }

    private static func isIdentifierBody(_ character: Character) -> Bool {
        isIdentifierHead(character) || character == "-" || (character.isASCII && character.isNumber)
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
        case "last_line": return Self.lastLine(of: step.output)
        case "exit": return step.exit.map(String.init) ?? ""
        case "stderr": return step.stderr
        default:
            if let value = step.fields[field] { return value }
            if step.failed { return "" }
            throw RPCError("workflow", "\(reference.placeholder) has no value.")
        }
    }

    private static func lastLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
    }
}

public enum JSONFields {
    public static func parse(_ text: String) throws -> [String: String] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw RPCError("workflow", "Expected a JSON object.")
        }
        var fields: [String: String] = [:]
        for (key, value) in object {
            fields[key] = try fieldText(value)
        }
        return fields
    }

    private static func fieldText(_ value: Any) throws -> String {
        switch value {
        case let string as String:
            return string
        case is NSNull:
            return ""
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return number.boolValue ? "true" : "false"
        default:
            let data = try JSONSerialization.data(withJSONObject: value,
                                                  options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        }
    }
}
