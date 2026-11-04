import Foundation
import Testing
import DicePluginCore
import OddFrogPluginAPI

private final class Faces {
    private var faces: [Int]
    private(set) var sides: [Int] = []
    init(_ faces: [Int]) {
        self.faces = faces
    }
    func next(_ sides: Int) -> Int {
        self.sides.append(sides)
        return faces.removeFirst()
    }
}

struct DiceExpressionTests {
    private func roll(_ text: String, _ faces: [Int]) throws -> DiceRoll {
        let expression = try #require(DiceExpression.parse(text))
        let source = Faces(faces)
        return try #require(expression.roll(source.next))
    }

    @Test func rollsDiceWithAModifier() throws {
        let roll = try roll("6d4+6", [3, 1, 4, 2, 4, 4])
        #expect(roll.total == 24)
        #expect(roll.breakdown == "[3, 1, 4, 2, 4, 4] + 6")
    }

    @Test func singleDieNeedsNoCount() throws {
        let single = try roll("d20", [17])
        #expect(single.total == 17 && single.breakdown == "[17]")
        #expect(try roll("5d20+20", [1, 2, 3, 4, 5]).total == 35)
        #expect(try roll("D%", [42]).total == 42)
    }

    @Test func dieSidesComeFromTheExpression() throws {
        let source = Faces([1, 1, 1])
        let expression = try #require(DiceExpression.parse("2d6 + d%"))
        _ = expression.roll(source.next)
        #expect(source.sides == [6, 6, 100])
    }

    @Test func advantageKeepsTheHigherRoll() throws {
        let max = try roll("max(d20, d20)", [7, 15])
        #expect(max.total == 15)
        #expect(max.breakdown == "max([7], [15])")
        let keep = try roll("2d20kh1+5", [7, 15])
        #expect(keep.total == 20)
        #expect(keep.breakdown == "[7\u{336}, 15] + 5")
    }

    @Test func disadvantageKeepsTheLowerRoll() throws {
        #expect(try roll("min(d20,d20)", [7, 15]).total == 7)
        #expect(try roll("2d20kl1", [7, 15]).total == 7)
    }

    @Test func keepingSeveralDropsTheRest() throws {
        let roll = try roll("4d6kh3", [3, 6, 1, 5])
        #expect(roll.total == 14)
        #expect(roll.breakdown == "[3, 6, 1\u{336}, 5]")
        #expect(try self.roll("4d6k", [3, 6, 1, 5]).total == 6)
    }

    @Test func arithmeticFollowsPrecedenceAndRoundsDown() throws {
        #expect(try roll("2 + d6 * 2", [4]).total == 10)
        #expect(try roll("(2 + d6) * 2", [4]).breakdown == "(2 + [4]) * 2")
        #expect(try roll("d6 / 2", [5]).total == 2)
        #expect(try roll("-d6 / 2", [5]).total == -3)
        #expect(try roll("d4 - 10", [1]).total == -9)
    }

    @Test func russianNotationWorks() throws {
        #expect(try roll("2к6+1", [2, 3]).total == 6)
    }

    @Test func textWithoutDiceIsLeftToTheCalculator() {
        for text in ["", "2+2", "12", "max(1, 2)", "d", "2d", "d0", "0d6", "101d6", "d1001", "2d20kh3", "d20+", "d20 d20",
                     "(d20", "dog", "d20x", "max(d20)d", "d２０"] {
            #expect(DiceExpression.parse(text) == nil, "\(text)")
        }
    }

    @Test func diceAreCappedAcrossTheExpression() {
        #expect(DiceExpression.parse("50d6 + 50d6") != nil)
        #expect(DiceExpression.parse("50d6 + 51d6") == nil)
        #expect(DiceExpression.parse(String(repeating: "-", count: 300) + "d6") == nil)
    }

    @Test func normalizedTextNamesTheRoll() throws {
        #expect(try #require(DiceExpression.parse("6D4+6")).text == "6d4 + 6")
        #expect(try #require(DiceExpression.parse("max(d20,d20)")).text == "max(d20, d20)")
        #expect(try #require(DiceExpression.parse("2d20k")).text == "2d20kh1")
        #expect(try #require(DiceExpression.parse("1d100")).text == "d%")
    }
}

struct DiceProviderTests {
    @Test func rowShowsTheTotalAndCopiesIt() {
        let source = Faces([3, 1, 4, 2, 4, 4])
        let rows = DiceProvider.respond(to: "6d4+6", die: source.next)
        #expect(rows.map(\.id) == ["roll"])
        #expect(rows[0].title == "24")
        #expect(rows[0].subtitle == "[3, 1, 4, 2, 4, 4] + 6")
        #expect(rows[0].answer == true)
        #expect(rows[0].primary == PluginAction(.copy, "24"))
        #expect(rows[0].secondary == PluginAction(.copy, "6d4 + 6: [3, 1, 4, 2, 4, 4] + 6 = 24"))
    }

    @Test func otherQueriesGetNoRows() {
        #expect(DiceProvider.respond(to: "Safari", die: { _ in 1 }).isEmpty)
        #expect(DiceProvider.respond(to: "2+2", die: { _ in 1 }).isEmpty)
    }

    @Test func divisionByZeroExplainsItself() {
        let rows = DiceProvider.respond(to: "d20 / (d2 - 1)", die: { _ in 1 })
        #expect(rows.map(\.title) == ["Can't roll d20 / (d2 - 1)"])
        #expect(rows[0].primary == nil)
    }

    @Test func handlerRollsWithinTheDie() async throws {
        let handler = DiceHandler()
        let operation = ProviderOperation(id: "test", service: { _, _ in throw RPCError("test", "No host services.") },
                                          emit: { _, _ in })
        let params = JSONValue.object([
            "input": try .encode(PluginQuery(query: "d6", fullQuery: "d6")),
            "context": try .encode(PluginContext()),
        ])
        for _ in 0..<50 {
            let rows = try await handler.handle("query", params: params, operation: operation).decode([PluginItem].self)
            #expect((1...6).contains(Int(rows.first?.title ?? "") ?? 0))
        }
    }
}
