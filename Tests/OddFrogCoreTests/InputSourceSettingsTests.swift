import Testing
@testable import OddFrogCore

struct InputSourceSettingsTests {
    @Test func inputSourceIsOffByDefault() throws {
        #expect(try Settings.parse("").launcher.inputSource == nil)
    }

    @Test func inputSourceRoundTrips() throws {
        let settings = try Settings.parse("""
        [launcher]
        input_source = "com.apple.keylayout.ABC"
        """)
        #expect(settings.launcher.inputSource == "com.apple.keylayout.ABC")
        #expect(settings.launcher.showPlugins)
        #expect(try Settings.parse(settings.serialized()).launcher.inputSource == "com.apple.keylayout.ABC")
    }

    @Test func blankInputSourceMeansOff() throws {
        let settings = try Settings.parse("""
        [launcher]
        input_source = "  "
        """)
        #expect(settings.launcher.inputSource == nil)
        #expect(try Settings.parse(Settings().serialized()).launcher.inputSource == nil)
    }
}
