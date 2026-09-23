enum SettingsPane: Int, CaseIterable {
    case general
    case items
    case plugins

    var title: String {
        switch self {
        case .general: return "General"
        case .items: return "Items"
        case .plugins: return "Plugins"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .items: return "square.grid.2x2"
        case .plugins: return "puzzlepiece.extension"
        }
    }
}
