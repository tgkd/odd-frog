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

    private let scroll = NSScrollView()
    private let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 492))
    private let placeholderLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private let discardButton = NSButton(title: "Discard and Close", target: nil, action: nil)

    private var session: DocumentSession?
    private var placeholder: String?
    private var autosave: Timer?
    private var pending: (reason: Reason, completion: ((Bool) -> Void)?)?
    private var notice: String?
    private var quitReply: ((Bool) -> Void)?
    private var quitTimer: Timer?

    init() {
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

    func present(_ view: PluginView, result: PluginResult, pluginName: String) {
        if let session, session.pluginID == result.pluginID, session.viewID == view.id {
            activateWindow()
            return
        }
        if let session, session.isDirty || session.inFlight != nil {
            flush(reason: .replace) { [weak self] saved in
                guard let self else { return }
                if saved {
                    show(view, result: result, pluginName: pluginName)
                } else {
                    activateWindow()
                }
            }
            return
        }
        show(view, result: result, pluginName: pluginName)
    }

    func pluginsDidReload() {
        guard let session, !session.invalidated else { return }
        autosave?.invalidate()
        autosave = nil
        session.invalidate(message: reloadMessage(session))
        refresh()
    }

    func prepareToTerminate(_ reply: @escaping (Bool) -> Void) -> Bool {
        guard let session, session.isDirty || session.inFlight != nil else { return false }
        quitReply = reply
        quitTimer?.invalidate()
        quitTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.answerQuit(false, message: "Save did not finish. Retry or Discard and Close, then quit again.")
            }
        }
        flush(reason: .quit) { [weak self] saved in
            self?.answerQuit(saved, message: nil)
        }
        return true
    }

    @objc func saveDocument(_ sender: Any?) {
        flush(reason: .manual)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let session, session.isDirty else { return true }
        if session.invalidated {
            refresh()
            return false
        }
        flush(reason: .close) { [weak self] saved in
            guard saved else { return }
            self?.window?.close()
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        guard let session else { return }
        session.edit(textView.string)
        notice = nil
        refresh()
        autosave?.invalidate()
        autosave = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush(reason: .autosave) }
        }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        window?.performClose(nil)
        return true
    }

    private func show(_ view: PluginView, result: PluginResult, pluginName: String) {
        autosave?.invalidate()
        autosave = nil
        pending = nil
        notice = nil
        session = DocumentSession(view: view, result: result, pluginName: pluginName)
        placeholder = view.placeholder
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
        notice = nil
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

    private func answerQuit(_ ok: Bool, message: String?) {
        guard let reply = quitReply else { return }
        quitReply = nil
        quitTimer?.invalidate()
        quitTimer = nil
        if let message {
            notice = message
            refresh()
        }
        reply(ok)
    }

    private func reloadMessage(_ session: DocumentSession) -> String {
        "\(session.pluginName) was reloaded. Your text is kept here; copy it or choose Discard and Close."
    }

    private func isSuperseded(_ error: any Error) -> Bool {
        guard let plugin = error as? PluginError, case .superseded = plugin else { return false }
        return true
    }

    private func refresh() {
        let message = notice ?? session?.error
        statusLabel.stringValue = message ?? ""
        discardButton.isHidden = message == nil
        retryButton.isHidden = message == nil || session?.invalidated == true
        placeholderLabel.stringValue = placeholder ?? ""
        placeholderLabel.isHidden = placeholder == nil || !textView.string.isEmpty
    }

    @objc private func retry() {
        flush(reason: .close) { [weak self] saved in
            guard saved else { return }
            self?.window?.close()
        }
    }

    @objc private func discardAndClose() {
        autosave?.invalidate()
        autosave = nil
        pending = nil
        notice = nil
        session = nil
        placeholder = nil
        textView.isEditable = true
        refresh()
        window?.close()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = self
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.isHidden = true
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        for (button, action) in [(retryButton, #selector(retry)), (discardButton, #selector(discardAndClose))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11)
            button.isHidden = true
            button.translatesAutoresizingMaskIntoConstraints = false
        }

        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(statusLabel)
        bar.addSubview(retryButton)
        bar.addSubview(discardButton)
        content.addSubview(scroll)
        content.addSubview(placeholderLabel)
        content.addSubview(bar)

        let padding = textView.textContainer?.lineFragmentPadding ?? 5
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.topAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 12 + padding),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: scroll.trailingAnchor, constant: -12),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: retryButton.leadingAnchor, constant: -8),
            retryButton.trailingAnchor.constraint(equalTo: discardButton.leadingAnchor, constant: -8),
            retryButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            discardButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            discardButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }
}
