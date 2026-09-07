import Foundation
import Testing
@testable import OddFrogCore

struct QuickActionTests {
    private let template = "https://duckduckgo.com/?q={query}"

    @Test func detectURLAcceptsRecognizableURLs() {
        #expect(QuickAction.detectURL("github.com") != nil)
        #expect(QuickAction.detectURL("docs.swift.org/path") != nil)
        #expect(QuickAction.detectURL("obsidian://open") != nil)
        #expect(QuickAction.detectURL("https://x.y") != nil)
    }

    @Test func detectURLRejectsNonURLs() {
        #expect(QuickAction.detectURL("hello world") == nil)
        #expect(QuickAction.detectURL("3.14") == nil)
        #expect(QuickAction.detectURL("localhost:3000") == nil)
        #expect(QuickAction.detectURL(".hidden") == nil)
        #expect(QuickAction.detectURL("word.") == nil)
    }

    @Test func terminalPrefixYieldsSingleTerminalAction() {
        let actions = QuickAction.fallbacks(for: "> ls -la", searchTemplate: template)
        #expect(actions == [.terminal("ls -la")])
    }

    @Test func nonURLQueryYieldsWebSearchFallback() {
        let actions = QuickAction.fallbacks(for: "odd frog", searchTemplate: template)
        #expect(actions.count == 1)
        guard case .webSearch(_, let url) = actions[0] else {
            Issue.record("expected a webSearch action")
            return
        }
        #expect(url.query == "q=odd%20frog")
    }

    @Test func noSearchTemplateAndNoURLYieldsNoFallbacks() {
        let actions = QuickAction.fallbacks(for: "odd frog", searchTemplate: nil)
        #expect(actions.isEmpty)
    }

    @Test func arithmeticQueryBecomesACalculatorAction() {
        guard let action = QuickAction.calculation(for: "2+2") else {
            Issue.record("expected a calculation action")
            return
        }
        #expect(action.title == "4")
        #expect(action.subtitle == "2+2")
        #expect(action.kindLabel == "Calculator")
        #expect(action.id == "quick:calc:2+2")
        #expect(action.copyText == "4")
    }

    @Test func calculatorTitleRoundsToSixPlaces() {
        #expect(QuickAction.calculation(for: "0.1+0.2")?.title == "0.3")
    }

    @Test func unitQueryBecomesAUnitsAction() {
        guard let action = QuickAction.calculation(for: "100 km in mi") else {
            Issue.record("expected a calculation action")
            return
        }
        #expect(action.title == "62.1371 mi")
        #expect(action.subtitle == "100 km → mi")
        #expect(action.kindLabel == "Units")
        #expect(action.copyText == "62.137119")
        #expect(QuickAction.calculation(for: "2+2")?.kindLabel == "Calculator")
    }

    @Test func plainTextAndBareNumbersAreNotCalculations() {
        #expect(QuickAction.calculation(for: "safari") == nil)
        #expect(QuickAction.calculation(for: "42") == nil)
    }
}
