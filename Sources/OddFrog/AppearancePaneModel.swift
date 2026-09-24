import AppKit
import Observation
import OddFrogCore

@Observable
@MainActor
final class AppearancePaneModel {
    private(set) var appearance = OddFrogCore.Settings.Appearance()

    @ObservationIgnored var onChange: ((OddFrogCore.Settings.Appearance) -> Void)?

    let families: [String]

    init() {
        families = NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func show(_ appearance: OddFrogCore.Settings.Appearance) {
        guard appearance != self.appearance else { return }
        self.appearance = appearance
    }

    var selectedFamily: String? {
        guard let family = appearance.fontFamily, families.contains(family) else { return nil }
        return family
    }

    var previewFont: NSFont {
        ContentFont(appearance).font(.body)
    }

    func setTheme(_ theme: OddFrogCore.Settings.Appearance.Theme) {
        commit(OddFrogCore.Settings.Appearance(theme: theme, fontFamily: appearance.fontFamily, fontSize: appearance.fontSize))
    }

    func setFamily(_ family: String?) {
        commit(OddFrogCore.Settings.Appearance(theme: appearance.theme, fontFamily: family, fontSize: appearance.fontSize))
    }

    func setSize(_ size: Double) {
        commit(OddFrogCore.Settings.Appearance(theme: appearance.theme, fontFamily: appearance.fontFamily, fontSize: size))
    }

    private func commit(_ updated: OddFrogCore.Settings.Appearance) {
        guard updated != appearance else { return }
        appearance = updated
        onChange?(updated)
    }
}
