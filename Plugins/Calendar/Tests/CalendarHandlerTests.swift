import Foundation
import Testing
import CalendarPluginCore
import OddFrogPluginAPI

private actor ServiceCounter {
    private(set) var calls = 0
    func record() {
        calls += 1
    }
}

struct CalendarHandlerTests {
    private func operation(_ counter: ServiceCounter) -> ProviderOperation {
        ProviderOperation(id: "test", service: { _, _ in
            await counter.record()
            throw RPCError("test", "unexpected service call")
        }, emit: { _, _ in })
    }

    private func params(_ input: some Encodable) throws -> JSONValue {
        .object(["apiVersion": .number(2), "input": try .encode(input)])
    }

    private func activation(_ actionID: String) -> PluginActivation {
        PluginActivation(actionID: actionID, payload: .object([:]),
                         item: CalendarProvider.monthItem(), argument: nil)
    }

    @Test func monthQueryAnswersWithoutCalendarServices() async throws {
        let counter = ServiceCounter()
        let query = PluginQuery(query: "month", fullQuery: "cal month", maxResults: 8)
        let items = try await CalendarHandler().handle("query", params: params(query), operation: operation(counter))
            .decode([PluginItem].self)
        #expect(items == [CalendarProvider.monthItem()])
        #expect(await counter.calls == 0)
    }

    @Test func monthActivationReturnsAMonthView() async throws {
        let counter = ServiceCounter()
        let effects = try await CalendarHandler().handle("activate", params: params(activation("month")),
                                                         operation: operation(counter)).decode(PluginEffects.self)
        #expect(effects.view?.kind == .month)
        #expect(await counter.calls == 0)
    }

    @Test func unknownActionsAreRefused() async throws {
        let counter = ServiceCounter()
        do {
            _ = try await CalendarHandler().handle("activate", params: params(activation("nope")),
                                                   operation: operation(counter))
            Issue.record("Expected an unknown action to be refused")
        } catch let error as RPCError {
            #expect(error.code == "action")
        }
    }
}
