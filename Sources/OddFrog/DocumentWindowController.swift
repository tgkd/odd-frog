import AppKit
import OddFrogCore
import OddFrogPluginAPI

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private enum Reason {
        case autosave, manual, close, quit, replace
        var blocking: Bool {
            switch self {
            case .close, .quit, .replace: return true
            case .autosave, .manual: return false
            }
        }
    }

    var performSave: ((DocumentSession, Int, String, @escaping (Result<PluginEffects, any Error>) -> Void) -> Void)?

    private let scroll = NSTextView.scrollablePlainDocumentContentTextView()
    private let textView: NSTextView

    private var session: DocumentSession?
    private var autosave: Timer?
    private var pending: (reason: Reason, completion: ((Bool) -> Void)?)?
    private var choosing = false
    private var quitReply: ((Bool) -> Void)?
    private var quitTimer: Timer?

    init() {
        textView = scroll.documentView as! NSTextView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("document")
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func present(_ view: PluginView, save: PluginAction, result: PluginResult, pluginName: String) {
        if let session, session.pluginID == result.pluginID, session.viewID == view.id {
            activateWindow()
            return
        }
        if let session, session.isDirty || session.inFlight != nil {
            flush(reason: .replace) { [weak self] saved in
                guard let self else { return }
                if saved {
                    show(view, save: save, result: result, pluginName: pluginName)
                } else {
                    activateWindow()
                    presentChoices(nil)
                }
            }
            return
        }
        show(view, save: save, result: result, pluginName: pluginName)
    }

    func pluginsDidReload() {
        guard let session, !session.invalidated else { return }
        autosave?.invalidate()
        autosave = nil
        session.invalidate(message: reloadMessage(session))
        refresh()
        if session.isDirty, window?.isVisible == true {
            presentChoices(nil)
        }
    }

    func prepareToTerminate(_ reply: @escaping (Bool) -> Void) -> Bool {
        guard let session, session.isDirty || session.inFlight != nil else { return false }
        quitReply = reply
        quitTimer?.invalidate()
        quitTimer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.answerQuit(false, detail: "Saving did not finish in time, so Odd Frog did not quit.")
            }
        }
        RunLoop.main.add(quitTimer!, forMode: .common)
        flush(reason: .quit) { [weak self] saved in
            self?.answerQuit(saved, detail: nil)
        }
        return true
    }

    @objc func saveDocument(_ sender: Any?) {
        flush(reason: .manual)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let session, session.isDirty else { return true }
        if session.invalidated {
            presentChoices(nil)
        } else {
            saveAndClose()
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        guard let session else { return }
        session.edit(textView.string)
        refresh()
        autosave?.invalidate()
        autosave = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush(reason: .autosave) }
        }
    }

    private func show(_ view: PluginView, save: PluginAction, result: PluginResult, pluginName: String) {
        autosave?.invalidate()
        autosave = nil
        pending = nil
        session = DocumentSession(view: view, save: save, result: result, pluginName: pluginName)
        textView.isEditable = true
        textView.string = view.text
        textView.undoManager?.removeAllActions()
        window?.title = view.title
        refresh()
        activateWindow()
    }

    private func activateWindow() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
    }

    private func flush(reason: Reason, completion: ((Bool) -> Void)? = nil) {
        autosave?.invalidate()
        autosave = nil
        guard let session else {
            completion?(true)
            return
        }
        guard let snapshot = session.beginSave() else {
            if session.inFlight != nil, reason.blocking {
                pending = (reason, completion)
                return
            }
            completion?(!session.isDirty)
            return
        }
        if reason.blocking {
            textView.isEditable = false
        }
        refresh()
        guard let performSave else {
            settle(.failure(PluginError.message("This document has no way to save.")),
                   session: session, reason: reason, revision: snapshot.revision, completion: completion)
            return
        }
        performSave(session, snapshot.revision, snapshot.text) { [weak self] response in
            guard let self else { return }
            settle(response, session: session, reason: reason, revision: snapshot.revision, completion: completion)
        }
    }

    private func settle(_ response: Result<PluginEffects, any Error>, session: DocumentSession,
                        reason: Reason, revision: Int, completion: ((Bool) -> Void)?) {
        if reason.blocking {
            textView.isEditable = true
        }
        guard self.session === session else {
            completion?(false)
            return
        }
        switch response {
        case .success(let effects):
            session.acknowledge(revision: revision, title: effects.view?.title)
            window?.title = session.title
            refresh()
            if session.isDirty, reason.blocking {
                flush(reason: reason, completion: completion)
            } else {
                completion?(!session.isDirty)
            }
        case .failure(let error):
            let terminal = isSuperseded(error)
            let message = terminal ? reloadMessage(session) : "Save failed: \(error)"
            session.fail(revision: revision, message: message, terminal: terminal)
            refresh()
            completion?(false)
        }
        guard let pending else { return }
        self.pending = nil
        flush(reason: pending.reason, completion: pending.completion)
    }

    private func answerQuit(_ ok: Bool, detail: String?) {
        guard let reply = quitReply else { return }
        quitReply = nil
        quitTimer?.invalidate()
        quitTimer = nil
        reply(ok)
        if !ok {
            activateWindow()
            presentChoices(detail)
        }
    }

    private func saveAndClose() {
        flush(reason: .close) { [weak self] saved in
            guard let self else { return }
            if saved {
                window?.close()
            } else {
                presentChoices(nil)
            }
        }
    }

    private func discardAndClose() {
        autosave?.invalidate()
        autosave = nil
        pending = nil
        session = nil
        textView.isEditable = true
        refresh()
        window?.close()
    }

    private func presentChoices(_ detail: String?) {
        guard let window, let session, !choosing else { return }
        choosing = true
        let invalidated = session.invalidated
        let alert = NSAlert()
        if invalidated {
            alert.messageText = "\(session.pluginName) was reloaded"
            alert.informativeText = "Changes to “\(session.title)” can no longer be saved. Copy any text you want to keep, then choose Discard and Close."
            alert.addButton(withTitle: "Keep Editing")
            alert.addButton(withTitle: "Discard and Close").hasDestructiveAction = true
        } else {
            alert.messageText = "“\(session.title)” was not saved"
            alert.informativeText = detail ?? session.error ?? ""
            alert.addButton(withTitle: "Save and Close")
            alert.addButton(withTitle: "Keep Editing").keyEquivalent = "\u{1b}"
            alert.addButton(withTitle: "Discard and Close").hasDestructiveAction = true
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            choosing = false
            guard self.session === session else { return }
            if invalidated {
                if response == .alertSecondButtonReturn {
                    discardAndClose()
                }
            } else {
                switch response {
                case .alertFirstButtonReturn: saveAndClose()
                case .alertThirdButtonReturn: discardAndClose()
                default: break
                }
            }
        }
    }

    private func reloadMessage(_ session: DocumentSession) -> String {
        "\(session.pluginName) was reloaded. Changes are no longer saved."
    }

    private func isSuperseded(_ error: any Error) -> Bool {
        guard let plugin = error as? PluginError, case .superseded = plugin else { return false }
        return true
    }

    private func refresh() {
        window?.subtitle = session?.error ?? ""
    }

    private func buildContent() {
        textView.allowsUndo = true
        textView.font = ContentFont.current.font(.body)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.delegate = self
        window?.contentView = scroll
    }

    func applyContentFont() {
        textView.font = ContentFont.current.font(.body)
    }
}
