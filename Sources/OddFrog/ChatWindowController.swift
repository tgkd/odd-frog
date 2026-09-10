import AppKit
import OddFrogCore
import OddFrogPluginAPI

@MainActor
final class ChatWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private final class Capsule: NSView {
        override var wantsUpdateLayer: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureLayer()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            configureLayer()
        }

        override func updateLayer() {
            configureLayer()
        }

        private func configureLayer() {
            wantsLayer = true
            guard let layer else {
                return
            }
            layer.cornerRadius = 16
            layer.cornerCurve = .continuous
            layer.borderWidth = 1
            layer.masksToBounds = true
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.backgroundColor = NSColor.textBackgroundColor.cgColor
                layer.borderColor = NSColor.separatorColor.cgColor
            }
        }
    }

    var performSend: ((ChatSession, String, @escaping (Result<PluginEffects, any Error>) -> Void) -> UUID?)?
    var cancelSend: ((UUID) -> Void)?

    private let transcript = ChatTranscriptView()
    private let capsule = Capsule()
    private let inputScroll = NSScrollView()
    private let input = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 30))
    private let placeholderLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private var inputHeight: NSLayoutConstraint?

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
        window.setFrameAutosaveName("chat")
        window.center()
        super.init(window: window)
        window.delegate = self
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
        input.isEditable = true
        input.string = started.draft
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
        input.string = session.draft
        render()
        refresh()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let flight = inFlight {
            cancelSend?(flight.token)
        }
        inFlight = nil
        session = nil
        input.string = ""
        input.isEditable = true
        render()
        refresh()
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard let session else {
            return
        }
        session.edit(input.string)
        updateInputHeight()
        refresh()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            submit()
            return true
        case #selector(NSResponder.insertLineBreak(_:)):
            return false
        case #selector(NSResponder.cancelOperation(_:)):
            window?.performClose(nil)
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
        input.string = ""
        updateInputHeight()
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
            input.string = session.draft
        }
        inFlight = nil
        render()
        updateInputHeight()
        refresh()
        if !session.invalidated {
            window?.makeFirstResponder(input)
        }
    }

    @objc private func stop() {
        guard let flight = inFlight else {
            return
        }
        cancelSend?(flight.token)
    }

    private func render() {
        transcript.render(session?.messages ?? [], streaming: session?.outgoing?.replyID)
    }

    private func activateWindow() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
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
            statusLabel.stringValue = error
        } else if sending, let session {
            statusLabel.stringValue = "Waiting for \(session.pluginName)…"
        } else {
            statusLabel.stringValue = ""
        }
        stopButton.isHidden = !sending
        input.isEditable = session?.invalidated != true
        placeholderLabel.stringValue = session?.placeholder ?? ""
        placeholderLabel.isHidden = session?.placeholder == nil || !input.string.isEmpty
    }

    private func updateInputHeight() {
        guard let layout = input.layoutManager, let container = input.textContainer else {
            return
        }
        layout.ensureLayout(for: container)
        let font = input.font ?? .systemFont(ofSize: 14)
        let line = layout.defaultLineHeight(for: font)
        let padding = input.textContainerInset.height * 2
        let used = layout.usedRect(for: container).height
        inputHeight?.constant = min(max(used, line) + padding, line * 6 + padding)
    }

    private func buildContent() {
        guard let content = window?.contentView else {
            return
        }
        input.isRichText = false
        input.usesFontPanel = false
        input.importsGraphics = false
        input.allowsUndo = true
        input.font = .systemFont(ofSize: 14)
        input.textContainerInset = NSSize(width: 12, height: 7)
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        input.isAutomaticLinkDetectionEnabled = false
        input.isAutomaticSpellingCorrectionEnabled = false
        input.drawsBackground = false
        input.delegate = self
        input.minSize = NSSize(width: 0, height: 0)
        input.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        inputScroll.documentView = input
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.borderType = .noBorder
        inputScroll.drawsBackground = false
        inputScroll.translatesAutoresizingMaskIntoConstraints = false

        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(inputScroll)

        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.isHidden = true
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(placeholderLabel)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        stopButton.target = self
        stopButton.action = #selector(stop)
        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .small
        stopButton.font = .systemFont(ofSize: 11)
        stopButton.isHidden = true
        stopButton.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(statusLabel)
        bar.addSubview(stopButton)

        content.addSubview(transcript)
        content.addSubview(separator)
        content.addSubview(capsule)
        content.addSubview(bar)

        let padding = input.textContainer?.lineFragmentPadding ?? 5
        let height = capsule.heightAnchor.constraint(equalToConstant: 34)
        inputHeight = height
        NSLayoutConstraint.activate([
            transcript.topAnchor.constraint(equalTo: content.topAnchor),
            transcript.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            transcript.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            transcript.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: capsule.topAnchor, constant: -12),
            capsule.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            capsule.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            capsule.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -8),
            height,
            inputScroll.topAnchor.constraint(equalTo: capsule.topAnchor),
            inputScroll.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
            inputScroll.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
            inputScroll.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: capsule.topAnchor, constant: 7),
            placeholderLabel.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 12 + padding),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: capsule.trailingAnchor, constant: -12),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            statusLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: stopButton.leadingAnchor, constant: -8),
            stopButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            stopButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        updateInputHeight()
    }
}
