import AppKit
import OddFrogCore
import OddFrogPluginAPI

@MainActor
final class ChatWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSToolbarDelegate, NSToolbarItemValidation {
    var performSend: ((ChatSession, String, @escaping (Result<PluginEffects, any Error>) -> Void) -> UUID?)?
    var cancelSend: ((UUID) -> Void)?

    private static let stopItem = NSToolbarItem.Identifier("stop")

    private let transcript = ChatTranscriptView()
    private let input = NSTextField(string: "")
    private var session: ChatSession?
    private var inFlight: (id: Int, token: UUID)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 380, height: 320)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "chat")
        toolbar.delegate = self
        window.toolbar = toolbar
        window.setFrameAutosaveName("chat")
        window.center()

        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func present(_ view: PluginView, send: PluginAction, result: PluginResult, pluginName: String) {
        if let session, session.pluginID == result.pluginID, session.viewID == view.id {
            activateWindow()
            return
        }
        if let flight = inFlight {
            cancelSend?(flight.token)
        }
        inFlight = nil
        let started = ChatSession(view: view, send: send, result: result, pluginName: pluginName)
        session = started
        input.isEnabled = true
        input.stringValue = started.draft
        input.undoManager?.removeAllActions()
        window?.title = started.title
        render()
        refresh()
        activateWindow()
        if started.canSend, let prompt = view.prompt, !prompt.isEmpty {
            submit()
        }
    }

    func apply(_ delta: PluginMessageDelta, pluginID: String) {
        guard let session, session.pluginID == pluginID else {
            return
        }
        guard session.receive(delta) else {
            return
        }
        render()
    }

    func pluginsDidReload() {
        guard let session, !session.invalidated else {
            return
        }
        session.invalidate(message: reloadMessage(session))
        inFlight = nil
        input.stringValue = session.draft
        render()
        refresh()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let flight = inFlight {
            cancelSend?(flight.token)
        }
        inFlight = nil
        session = nil
        input.stringValue = ""
        input.isEnabled = true
        render()
        refresh()
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let session else {
            return
        }
        session.edit(input.stringValue)
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            submit()
            return true
        default:
            return false
        }
    }

    private func submit() {
        guard let session, let outgoing = session.beginSend() else {
            return
        }
        render()
        input.stringValue = ""
        refresh()
        guard let performSend else {
            finish(.failure(PluginError.message("This chat has no way to send.")), session: session, id: outgoing.id)
            return
        }
        let token = performSend(session, outgoing.text) { [weak self] response in
            self?.finish(response, session: session, id: outgoing.id)
        }
        if let token, session.outgoing?.id == outgoing.id {
            inFlight = (outgoing.id, token)
        }
    }

    private func finish(_ response: Result<PluginEffects, any Error>, session: ChatSession, id: Int) {
        guard self.session === session else {
            return
        }
        switch response {
        case .success(let effects):
            session.complete(id: id, view: effects.view)
            window?.title = session.title
        case .failure(let error):
            let terminal = isSuperseded(error)
            let message: String
            if terminal {
                message = reloadMessage(session)
            } else if error is CancellationError {
                message = "Stopped."
            } else {
                message = "Send failed: \(error)"
            }
            session.fail(id: id, message: message, terminal: terminal)
            input.stringValue = session.draft
        }
        inFlight = nil
        render()
        refresh()
        if !session.invalidated {
            focusInput()
        }
    }

    @objc private func stop(_ sender: Any?) {
        guard let flight = inFlight else {
            return
        }
        cancelSend?(flight.token)
    }

    private func render() {
        transcript.render(session?.messages ?? [], streaming: session?.outgoing?.replyID, assistant: session?.pluginName ?? "")
    }

    func applyContentFont() {
        input.font = ContentFont.current.font(.body)
        transcript.reloadAll()
    }

    private func activateWindow() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        focusInput()
    }

    private func focusInput() {
        guard input.currentEditor() == nil else {
            return
        }
        window?.makeFirstResponder(input)
    }

    private func reloadMessage(_ session: ChatSession) -> String {
        "\(session.pluginName) was reloaded. Close this window and open the chat again."
    }

    private func isSuperseded(_ error: any Error) -> Bool {
        guard let plugin = error as? PluginError, case .superseded = plugin else {
            return false
        }
        return true
    }

    private func refresh() {
        let sending = session?.isSending == true
        if let error = session?.error {
            window?.subtitle = error
        } else if sending, let session {
            window?.subtitle = "Waiting for \(session.pluginName)…"
        } else {
            window?.subtitle = ""
        }
        input.isEnabled = session?.invalidated != true
        input.placeholderString = session?.placeholder
        window?.toolbar?.validateVisibleItems()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.stopItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.stopItem]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.stopItem else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Stop"
        item.toolTip = "Stop"
        item.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
        item.target = self
        item.action = #selector(stop(_:))
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        item.itemIdentifier == Self.stopItem ? session?.isSending == true : true
    }

    private func buildContent() {
        guard let content = window?.contentView else {
            return
        }
        input.delegate = self
        input.font = ContentFont.current.font(.body)
        input.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let composer = NSView()
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(input)

        content.addSubview(transcript)
        content.addSubview(separator)
        content.addSubview(composer)

        NSLayoutConstraint.activate([
            transcript.topAnchor.constraint(equalTo: content.topAnchor),
            transcript.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            transcript.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            transcript.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: composer.topAnchor),
            composer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            input.leadingAnchor.constraint(equalTo: composer.layoutMarginsGuide.leadingAnchor),
            input.trailingAnchor.constraint(equalTo: composer.layoutMarginsGuide.trailingAnchor),
            input.topAnchor.constraint(equalTo: composer.layoutMarginsGuide.topAnchor),
            input.bottomAnchor.constraint(equalTo: composer.layoutMarginsGuide.bottomAnchor),
        ])
    }
}
