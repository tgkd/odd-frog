import AppKit

@MainActor
final class ChatMessageCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("message")

    private let speaker = NSTextField(labelWithString: "")
    private let body = NSTextField(wrappingLabelWithString: "")
    private let indicator = NSProgressIndicator()
    private let stack: NSStackView
    private var appliedFont: ContentFont?

    init() {
        indicator.style = .spinning

        let stack = NSStackView(views: [speaker, body, indicator])
        stack.orientation = .vertical
        stack.alignment = .leading
        self.stack = stack

        super.init(frame: .zero)
        identifier = Self.identifier
        textField = body

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalToSystemSpacingBelow: topAnchor, multiplier: 1),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyFonts()
    }

    required init?(coder: NSCoder) { nil }

    private func applyFonts() {
        guard appliedFont != ContentFont.current else { return }
        appliedFont = ContentFont.current
        speaker.font = ContentFont.current.font(.headline)
        body.font = ContentFont.current.font(.body)
    }

    func show(_ text: String, speaker name: String, waiting: Bool) {
        applyFonts()
        speaker.stringValue = name
        body.stringValue = text
        body.isHidden = waiting
        indicator.isHidden = !waiting
        if waiting {
            indicator.startAnimation(nil)
        } else {
            indicator.stopAnimation(nil)
        }
        indicator.setAccessibilityLabel("Waiting for \(name)")
    }
}
