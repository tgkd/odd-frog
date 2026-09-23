import AppKit

@MainActor
final class ResultRow: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultRowBackground")

    override var isEmphasized: Bool {
        get { true }
        set { _ = newValue }
    }
}
