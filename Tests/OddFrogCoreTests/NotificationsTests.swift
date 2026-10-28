import Foundation
import Testing
@testable import OddFrogCore

struct NotificationsTests {
    @Test func notificationsDefaultToOn() throws {
        #expect(try Settings.parse("").notifications.enabled)
    }

    @Test func notificationsCanBeTurnedOff() throws {
        let settings = try Settings.parse("""
        [notifications]
        enabled = false
        """)
        #expect(!settings.notifications.enabled)
        #expect(try Settings.parse(settings.serialized()).notifications.enabled == false)
    }

    @Test func notifyURLReadsTitleAndBody() throws {
        let url = try #require(URL(string: "odd-frog://notify?title=Download%20complete&body=clip.mp4%20%E2%80%94%20done"))
        let request = try #require(NotifyURL(url))
        #expect(request.title == "Download complete")
        #expect(request.body == "clip.mp4 — done")
    }

    @Test func notifyURLTitleIsOptional() throws {
        let url = try #require(URL(string: "odd-frog://notify?body=Caffeine%20on"))
        #expect(NotifyURL(url)?.title == nil)
        #expect(NotifyURL(url)?.body == "Caffeine on")
    }

    @Test func notifyURLRejectsMissingBodyAndOtherHosts() throws {
        let rejected = ["odd-frog://notify?title=Only", "odd-frog://notify?body=%20%20", "odd-frog://open?body=x", "https://notify?body=x"]
        for string in rejected {
            let url = try #require(URL(string: string))
            #expect(NotifyURL(url) == nil)
        }
    }

    @Test func notifyURLBoundsLength() throws {
        let long = String(repeating: "a", count: 5000)
        let url = try #require(URL(string: "odd-frog://notify?body=\(long)"))
        #expect(NotifyURL(url)?.body.count == NotifyURL.maxLength)
    }
}
