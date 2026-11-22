import Foundation
import Testing
import OddFrogPluginAPI
import WorkflowsPluginCore

struct TemplateTests {
    private func render(_ source: String, _ values: WorkflowValues) throws -> String {
        try Template.parse(source).render(values)
    }

    @Test func parsesInputAndStepFieldPlaceholders() {
        let template = Template.parse("Idea: {input} for {draft.product}.")
        #expect(template.parts == [
            .text("Idea: "), .value(ValueReference(name: "input")), .text(" for "),
            .value(ValueReference(name: "draft", field: "product")), .text("."),
        ])
    }

    @Test func otherBracesStayLiteral() throws {
        let source = "Return {title, product, work_type, body}. {} {1x} {a.b.c} } {x"
        let template = Template.parse(source)
        #expect(template.references.isEmpty)
        #expect(try template.render(WorkflowValues(input: "")) == source)
    }

    @Test func namesMayContainUnderscoresAndDashes() {
        #expect(Template.parse("{_a-1.work_type-2}").references == [ValueReference(name: "_a-1", field: "work_type-2")])
    }

    @Test func doubleBraceIsALiteralBrace() throws {
        #expect(try render("{{input}", WorkflowValues(input: "x")) == "{input}")
        #expect(try render("{{{input}", WorkflowValues(input: "x")) == "{x")
        #expect(try render("a {{ b", WorkflowValues(input: "x")) == "a { b")
    }

    @Test func substitutedValuesAreNeverScannedAgain() throws {
        let values = WorkflowValues(input: "see {review.file} and {input}", steps: ["review": StepValues(fields: ["file": "/tmp/x"])])
        #expect(try render("<{input}>", values) == "<see {review.file} and {input}>")
    }

    @Test func argvElementsAreNeverSplit() throws {
        let argv = ["/bin/echo", "{input}", "Title={draft.title}"].map(Template.parse)
        let values = WorkflowValues(input: "two words  here", steps: ["draft": StepValues(fields: ["title": "a b"])])
        #expect(try argv.map { try $0.render(values) } == ["/bin/echo", "two words  here", "Title=a b"])
    }

    @Test func tildeInValuesIsNotExpanded() throws {
        #expect(try render("{input}", WorkflowValues(input: "~/secret")) == "~/secret")
    }

    @Test func resolvesStandardFields() throws {
        let values = WorkflowValues(input: "", steps: [
            "run": StepValues(output: "first\n  last one  \n\n", exit: 3, stderr: "warn"),
        ])
        #expect(try render("{run.output}", values) == "first\n  last one  \n\n")
        #expect(try render("{run.last_line}", values) == "last one")
        #expect(try render("{run.exit}", values) == "3")
        #expect(try render("{run.stderr}", values) == "warn")
    }

    @Test func missingExitIsEmpty() throws {
        #expect(try render("[{run.exit}]", WorkflowValues(input: "", steps: ["run": StepValues()])) == "[]")
    }

    @Test func standardNamesWinOverJSONFields() throws {
        let values = WorkflowValues(input: "", steps: ["draft": StepValues(output: "raw", fields: ["output": "json", "title": "T"])])
        #expect(try render("{draft.output} {draft.title}", values) == "raw T")
    }

    @Test func failedStepGivesEmptyValuesForUnsetFields() throws {
        let values = WorkflowValues(input: "", steps: ["draft": StepValues(exit: 1, failed: true)])
        #expect(try render("[{draft.output}|{draft.title}|{draft.exit}|{draft.last_line}]", values) == "[||1|]")
    }

    @Test func missingJSONFieldIsAnError() {
        let values = WorkflowValues(input: "", steps: ["draft": StepValues(fields: ["title": "T"])])
        #expect(throws: RPCError("workflow", "{draft.titel} has no value.")) { try render("{draft.titel}", values) }
    }

    @Test func missingStepIsAnError() {
        #expect(throws: RPCError("workflow", "{draft.title} has no value.")) {
            try render("{draft.title}", WorkflowValues(input: ""))
        }
    }

    @Test func jsonFieldsConvertValuesToText() throws {
        let fields = try JSONFields.parse("""
          {"s": "text", "i": 42, "f": 1.5, "whole": 3.0, "t": true, "n": null, "o": {"b": 1, "a": "x/y"}, "a": [1, "two"]}

        """)
        #expect(fields == [
            "s": "text", "i": "42", "f": "1.5", "whole": "3", "t": "true", "n": "",
            "o": #"{"a":"x/y","b":1}"#, "a": #"[1,"two"]"#,
        ])
    }

    @Test(arguments: ["[1, 2]", "\"text\"", "not json", "```json\n{\"a\": 1}\n```", ""])
    func jsonFieldsRejectNonObjects(_ text: String) {
        #expect(throws: RPCError("workflow", "Expected a JSON object.")) { try JSONFields.parse(text) }
    }
}
