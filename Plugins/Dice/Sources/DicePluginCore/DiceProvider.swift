import Foundation
import OddFrogPluginAPI

public enum DiceProvider {
    public static func respond(to text: String, die: (Int) -> Int) -> [PluginItem] {
        guard let expression = DiceExpression.parse(text) else {
            return []
        }
        guard let roll = expression.roll(die) else {
            return [PluginItem(id: "roll", title: "Can't roll \(expression.text)",
                               subtitle: "Division by zero or a number too large", kind: "Dice",
                               symbol: "exclamationmark.triangle", answer: true)]
        }
        let total = String(roll.total)
        return [PluginItem(id: "roll", title: total, subtitle: roll.breakdown, kind: "Dice", symbol: "dice",
                           primary: PluginAction(.copy, total),
                           secondary: PluginAction(.copy, "\(expression.text): \(roll.breakdown) = \(total)"),
                           answer: true)]
    }
}
