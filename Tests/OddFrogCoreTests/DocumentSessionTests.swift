import Foundation
import Testing
import OddFrogPluginAPI
@testable import OddFrogCore

@MainActor
struct DocumentSessionTests {
    private func make(title: String = "Note", text: String = "hello", placeholder: String? = nil) -> DocumentSession {
        let view = PluginView(id: "n1", title: title, text: text, placeholder: placeholder,
                              save: PluginAction(.callback, "save"))
        let result = PluginResult(pluginID: "notes", item: PluginItem(id: "n1", title: title))
        return DocumentSession(view: view, save: PluginAction(.callback, "save"), result: result, pluginName: "Notes")
    }

    @Test func theViewSeedsTitleAndTextAndTheSessionStartsClean() {
        let session = make()
        #expect(session.title == "Note")
        #expect(session.text == "hello")
        #expect(session.pluginID == "notes")
        #expect(session.viewID == "n1")
        #expect(!session.isDirty)
        #expect(!session.canSave)
        #expect(session.beginSave() == nil)
        #expect(session.error == nil)
    }

    @Test func editingMakesItDirtyAndOnlyOneSaveRunsAtATime() {
        let session = make()
        session.edit("hello")
        #expect(!session.isDirty)
        session.edit("hello world")
        #expect(session.isDirty)
        #expect(session.canSave)
        let snapshot = session.beginSave()
        #expect(snapshot?.revision == 1)
        #expect(snapshot?.text == "hello world")
        #expect(session.inFlight == 1)
        #expect(session.beginSave() == nil)
    }

    @Test func anEditDuringASaveKeepsTheSessionDirtyAndTheNextSaveCarriesTheNewerText() throws {
        let session = make()
        session.edit("first")
        let snapshot = try #require(session.beginSave())
        session.edit("second")
        session.acknowledge(revision: snapshot.revision, title: nil)
        #expect(session.inFlight == nil)
        #expect(session.isDirty)
        let next = session.beginSave()
        #expect(next?.text == "second")
        #expect(next?.revision == 2)
        session.acknowledge(revision: 2, title: nil)
        #expect(!session.isDirty)
    }

    @Test func acknowledgingARevisionThatIsNotInFlightIsIgnored() {
        let session = make()
        session.edit("first")
        session.acknowledge(revision: 1, title: "Ignored")
        #expect(session.isDirty)
        #expect(session.title == "Note")
        _ = session.beginSave()
        session.acknowledge(revision: 99, title: "Ignored")
        #expect(session.inFlight == 1)
        #expect(session.isDirty)
    }

    @Test func aNonTerminalFailureKeepsTheTextSavableAndTheNextEditClearsTheError() {
        let session = make()
        session.edit("first")
        _ = session.beginSave()
        session.fail(revision: 1, message: "Save failed: nope", terminal: false)
        #expect(session.error == "Save failed: nope")
        #expect(!session.invalidated)
        #expect(session.canSave)
        #expect(session.beginSave()?.text == "first")
        session.edit("second")
        #expect(session.error == nil)
    }

    @Test func aTerminalFailureStopsSavingWhileTheTextSurvives() {
        let session = make()
        session.edit("draft")
        _ = session.beginSave()
        session.fail(revision: 1, message: "Notes was reloaded.", terminal: true)
        #expect(session.invalidated)
        #expect(!session.canSave)
        #expect(session.beginSave() == nil)
        #expect(session.isDirty)
        #expect(session.text == "draft")
        session.edit("draft plus")
        #expect(session.error == "Notes was reloaded.")
        #expect(session.text == "draft plus")
        #expect(!session.canSave)
    }

    @Test func invalidateStopsSavingAndKeepsTheBuffer() {
        let session = make()
        session.edit("draft")
        _ = session.beginSave()
        session.invalidate(message: "Notes was reloaded.")
        #expect(session.invalidated)
        #expect(session.inFlight == nil)
        #expect(session.error == "Notes was reloaded.")
        #expect(session.isDirty)
        #expect(session.text == "draft")
        #expect(!session.canSave)
    }

    @Test func acknowledgeUpdatesTheTitleWhenTheProviderReturnsOne() {
        let session = make()
        session.edit("draft")
        _ = session.beginSave()
        session.acknowledge(revision: 1, title: "Draft")
        #expect(session.title == "Draft")
        #expect(!session.isDirty)
        session.edit("draft again")
        _ = session.beginSave()
        session.acknowledge(revision: 2, title: nil)
        #expect(session.title == "Draft")
    }
}
