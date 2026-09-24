import Observation
import OddFrogCore

@Observable
@MainActor
final class CalendarWindowModel {
    var browser: CalendarBrowser

    init(browser: CalendarBrowser) {
        self.browser = browser
    }
}
