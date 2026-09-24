import Foundation
import Testing
import OddFrogPluginAPI
@testable import OddFrogCore

struct AppearanceSettingsTests {
    @Test func missingAppearanceTableUsesDefaults() throws {
        let settings = try Settings.parse("")
        #expect(settings.appearance == Settings.Appearance())
    }

    @Test func appearanceValuesParse() throws {
        let settings = try Settings.parse("""
        [appearance]
        theme = "dark"
        font_family = "Menlo"
        font_size = 15
        """)
        #expect(settings.appearance.theme == .dark)
        #expect(settings.appearance.fontFamily == "Menlo")
        #expect(settings.appearance.fontSize == 15)
    }

    @Test func fontSizeClampsToRange() throws {
        let large = try Settings.parse("""
        [appearance]
        font_size = 30
        """)
        #expect(large.appearance.fontSize == 24)
        let small = try Settings.parse("""
        [appearance]
        font_size = 4
        """)
        #expect(small.appearance.fontSize == 10)
    }

    @Test func fractionalFontSizeIsAccepted() throws {
        let settings = try Settings.parse("""
        [appearance]
        font_size = 14.5
        """)
        #expect(settings.appearance.fontSize == 14.5)
    }

    @Test func unknownThemeFallsBackToSystem() throws {
        let settings = try Settings.parse("""
        [appearance]
        theme = "neon"
        """)
        #expect(settings.appearance.theme == .system)
    }

    @Test func whitespaceFontFamilyBecomesNil() throws {
        let settings = try Settings.parse("""
        [appearance]
        font_family = "  "
        """)
        #expect(settings.appearance.fontFamily == nil)
    }

    @Test func nonDefaultAppearanceRoundTrips() throws {
        let settings = Settings(appearance: Settings.Appearance(theme: .dark, fontFamily: "Menlo", fontSize: 18))
        #expect(try Settings.parse(settings.serialized()).appearance == settings.appearance)
    }

    @Test func defaultAppearanceOmitsFontFamilyKey() throws {
        let settings = Settings()
        let text = try settings.serialized()
        #expect(!text.contains("font_family"))
        #expect(try Settings.parse(text).appearance == Settings.Appearance())
    }
}
