import Foundation
import Testing
import OddFrogPluginAPI
@testable import OddFrogCore

@MainActor
struct ChatSessionTests {
    private func make(messages: [PluginMessage] = [], prompt: String? = nil,
                      placeholder: String? = "Ask anything") -> ChatSession {
        let view = PluginView(id: "c1", title: "Chat", messages: messages, placeholder: placeholder,
                              prompt: prompt, send: PluginAction(.callback, "send"))
        let result = PluginResult(pluginID: "chat", item: PluginItem(id: "c1", title: "Chat"))
        return ChatSession(view: view, send: PluginAction(.callback, "send"), result: result, pluginName: "Chat")
    }

    @Test func theViewSeedsTitleMessagesPlaceholderAndDraft() {
        let session = make(messages: [PluginMessage(id: "m1", role: .user, text: "hello")], prompt: "hi there")
        #expect(session.title == "Chat")
        #expect(session.pluginID == "chat")
        #expect(session.viewID == "c1")
        #expect(session.messages.map(\.id) == ["m1"])
        #expect(session.placeholder == "Ask anything")
        #expect(session.draft == "hi there")
        #expect(session.canSend)
        #expect(!session.isSending)
    }

    @Test func beginSendNeedsANonBlankDraftAndAppendsBothMessages() {
        let session = make(prompt: "   ")
        #expect(!session.canSend)
        #expect(session.beginSend() == nil)
        session.edit("hello")
        let outgoing = session.beginSend()
        #expect(outgoing?.id == 1)
        #expect(outgoing?.text == "hello")
        #expect(session.messages.map(\.role) == [.user, .assistant])
        #expect(session.messages[0].text == "hello")
        #expect(session.messages[1].text.isEmpty)
        #expect(session.outgoing?.replyID == session.messages[1].id)
        #expect(session.draft.isEmpty)
        #expect(session.isSending)
        #expect(!session.canSend)
        #expect(session.beginSend() == nil)
    }

    @Test func deltasForAnotherViewAreIgnoredAndMatchingOnesRenameAndAppend() {
        let session = make()
        session.edit("hello")
        _ = session.beginSend()
        #expect(!session.receive(PluginMessageDelta(viewID: "other", messageID: "m2", delta: "no")))
        #expect(session.receive(PluginMessageDelta(viewID: "c1", messageID: "m2", delta: "Hel")))
        #expect(session.receive(PluginMessageDelta(viewID: "c1", messageID: "m2", delta: "lo")))
        #expect(session.messages[1].id == "m2")
        #expect(session.messages[1].text == "Hello")
        #expect(session.outgoing?.replyID == "m2")
    }

    @Test func deltasOutsideASendAreIgnored() {
        let session = make()
        #expect(!session.receive(PluginMessageDelta(viewID: "c1", messageID: "m2", delta: "Hi")))
        #expect(session.messages.isEmpty)
    }

    @Test func completeWithAViewReplacesTheTranscriptAndTitle() throws {
        let session = make()
        session.edit("hello")
        let outgoing = try #require(session.beginSend())
        let view = PluginView(id: "c1", title: "Greeting",
                              messages: [PluginMessage(id: "m1", role: .user, text: "hello"),
                                         PluginMessage(id: "m2", role: .assistant, text: "Hello!")],
                              send: PluginAction(.callback, "send"))
        session.complete(id: outgoing.id, view: view)
        #expect(session.title == "Greeting")
        #expect(session.messages.map(\.id) == ["m1", "m2"])
        #expect(session.messages[1].text == "Hello!")
        #expect(!session.isSending)
        #expect(session.error == nil)
    }

    @Test func completeWithoutAViewKeepsTheStreamedReply() throws {
        let session = make()
        session.edit("hello")
        let outgoing = try #require(session.beginSend())
        _ = session.receive(PluginMessageDelta(viewID: "c1", messageID: "m2", delta: "Hi"))
        session.complete(id: outgoing.id, view: nil)
        #expect(session.title == "Chat")
        #expect(session.messages.count == 2)
        #expect(session.messages[1].text == "Hi")
        #expect(!session.isSending)
    }

    @Test func failRemovesBothMessagesAndRestoresTheDraft() throws {
        let session = make(messages: [PluginMessage(id: "m0", role: .assistant, text: "ready")])
        session.edit("hello")
        let outgoing = try #require(session.beginSend())
        _ = session.receive(PluginMessageDelta(viewID: "c1", messageID: "m2", delta: "Hi"))
        session.fail(id: outgoing.id, message: "Send failed.", terminal: false)
        #expect(session.messages.map(\.id) == ["m0"])
        #expect(session.draft == "hello")
        #expect(session.error == "Send failed.")
        #expect(!session.invalidated)
        #expect(session.canSend)
    }

    @Test func terminalFailuresAndInvalidateStopFurtherSends() throws {
        let session = make()
        session.edit("hello")
        let outgoing = try #require(session.beginSend())
        session.fail(id: outgoing.id, message: "Reloaded.", terminal: true)
        #expect(session.invalidated)
        #expect(session.draft == "hello")
        #expect(!session.canSend)
        #expect(session.beginSend() == nil)

        let other = make()
        other.edit("hello")
        _ = other.beginSend()
        other.invalidate(message: "Reloaded.")
        #expect(other.invalidated)
        #expect(other.error == "Reloaded.")
        #expect(other.draft == "hello")
        #expect(other.messages.isEmpty)
        #expect(!other.isSending)
        #expect(!other.canSend)
    }

    @Test func invalidateWithoutASendStillBlocksSending() {
        let session = make(prompt: "hello")
        session.invalidate(message: "Reloaded.")
        #expect(session.invalidated)
        #expect(session.error == "Reloaded.")
        #expect(session.draft == "hello")
        #expect(!session.canSend)
    }

    @Test func staleCompleteAndFailIdentifiersAreIgnored() {
        let session = make()
        session.edit("hello")
        _ = session.beginSend()
        session.complete(id: 99, view: nil)
        #expect(session.isSending)
        session.fail(id: 99, message: "Nope.", terminal: true)
        #expect(session.isSending)
        #expect(session.error == nil)
        #expect(!session.invalidated)
        #expect(session.messages.count == 2)
    }
}
