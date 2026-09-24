enum SettingsPane: Int, CaseIterable {
    case general
    case appearance
    case items
    case plugins

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .items: return "Items"
        case .plugins: return "Plugins"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "circle.lefthalf.filled"
        case .items: return "square.grid.2x2"
        case .plugins: return "puzzlepiece.extension"
        }
    }
}
