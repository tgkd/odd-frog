import AppKit
import OddFrogPluginAPI

@MainActor
final class ChatTranscriptView: NSView {
    @MainActor private enum Style {
        static let rowSpacing: CGFloat = 8
        static let edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        static let cornerRadius: CGFloat = 16
        static let bubbleInsets = NSSize(width: 12, height: 8)
        static let bodyFont = NSFont.systemFont(ofSize: 14)
        static let maxWidthRatio: CGFloat = 0.75
        static let userFill = NSColor.controlAccentColor
        static let userText = NSColor.white
        static let replyFill = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0x3B / 255, green: 0x3B / 255, blue: 0x3D / 255, alpha: 1)
                : NSColor(red: 0xE9 / 255, green: 0xE9 / 255, blue: 0xEB / 255, alpha: 1)
        }
        static let replyText = NSColor.labelColor
        static let typingGlyph = "…"
        static let stickyBottom: CGFloat = 24
    }

    private final class Bubble: NSView {
        let role: PluginMessage.Role
        private let container = NSView()
        private let label = NSTextField(wrappingLabelWithString: "")

        init(role: PluginMessage.Role) {
            self.role = role
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            container.wantsLayer = true
            container.layer?.cornerRadius = Style.cornerRadius
            container.layer?.cornerCurve = .continuous
            container.layer?.masksToBounds = true
            container.translatesAutoresizingMaskIntoConstraints = false
            label.isSelectable = true
            label.isEditable = false
            label.drawsBackground = false
            label.isBezeled = false
            label.font = Style.bodyFont
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textColor = role == .user ? Style.userText : Style.replyText
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            addSubview(container)
            let width = container.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: Style.maxWidthRatio)
            width.priority = .required
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: topAnchor),
                container.bottomAnchor.constraint(equalTo: bottomAnchor),
                width,
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: Style.bubbleInsets.height),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Style.bubbleInsets.height),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Style.bubbleInsets.width),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Style.bubbleInsets.width),
            ])
            if role == .user {
                NSLayoutConstraint.activate([
                    container.trailingAnchor.constraint(equalTo: trailingAnchor),
                    container.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    container.leadingAnchor.constraint(equalTo: leadingAnchor),
                    container.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                ])
            }
            applyFill()
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyFill()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            applyFill()
        }

        private func applyFill() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                container.layer?.backgroundColor = (role == .user ? Style.userFill : Style.replyFill).cgColor
            }
        }

        func show(_ text: String, typing: Bool) {
            label.stringValue = typing ? Style.typingGlyph : text
            label.textColor = typing ? .secondaryLabelColor : (role == .user ? Style.userText : Style.replyText)
        }
    }

    private final class DocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    private let scroll = NSScrollView()
    private let document = DocumentView()
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = Style.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: Style.edgeInsets.left),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -Style.edgeInsets.right),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: Style.edgeInsets.top),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -Style.edgeInsets.bottom),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ messages: [PluginMessage], streaming replyID: String?) {
        let sticky = isNearBottom()
        var rows = stack.arrangedSubviews.compactMap { $0 as? Bubble }
        var index = 0
        while index < messages.count {
            if index < rows.count, rows[index].role != messages[index].role {
                for row in rows[index...] {
                    stack.removeArrangedSubview(row)
                    row.removeFromSuperview()
                }
                rows.removeSubrange(index...)
            }
            if index >= rows.count {
                let bubble = Bubble(role: messages[index].role)
                stack.addArrangedSubview(bubble)
                rows.append(bubble)
            }
            let message = messages[index]
            rows[index].show(message.text, typing: message.id == replyID && message.text.isEmpty)
            index += 1
        }
        if rows.count > messages.count {
            for row in rows[messages.count...] {
                stack.removeArrangedSubview(row)
                row.removeFromSuperview()
            }
        }
        document.layoutSubtreeIfNeeded()
        if sticky {
            scrollToBottom()
        }
    }

    private func isNearBottom() -> Bool {
        let visible = scroll.contentView.documentVisibleRect
        let height = document.frame.height
        guard height > visible.height else {
            return true
        }
        return visible.maxY >= height - Style.stickyBottom
    }

    private func scrollToBottom() {
        let height = document.frame.height
        let visible = scroll.contentView.bounds.height
        guard height > visible else {
            return
        }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: height - visible))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
