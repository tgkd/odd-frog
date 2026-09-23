import AppKit
import OddFrogCore
import SwiftUI

@MainActor
final class LinkManagerController: NSWindowController {
    var onApply: ((CommandItem?, LinkDraft?) throws -> [CommandItem])?
    private let model = LinkManagerModel()

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 490),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Manage Links"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        model.onDone = { [weak self] in
            guard let window = self?.window else { return }
            window.sheetParent?.endSheet(window)
        }
    }

    required init?(coder: NSCoder) { nil }

    func present(links: [CommandItem], for parent: NSWindow) {
        guard let window, window.sheetParent == nil else { return }
        model.onApply = onApply
        let host = NSHostingController(rootView: LinkManagerView(model: model))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 580, height: 490))
        model.reset(links: links)
        parent.beginSheet(window)
    }
}
