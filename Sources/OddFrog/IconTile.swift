import AppKit

@MainActor
final class IconTile: NSView {
    private let tint: NSColor
    private let radius: CGFloat
    private let symbolView = NSImageView()

    override var wantsUpdateLayer: Bool { true }

    init(color: NSColor, symbol: String, side: CGFloat, radius: CGFloat, pointSize: CGFloat) {
        tint = color
        self.radius = radius
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        symbolView.contentTintColor = .white
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        configureLayer()
    }

    required init?(coder: NSCoder) { nil }

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
        guard let layer else { return }
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = tint.cgColor
        }
    }
}
