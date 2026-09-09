import CoreGraphics
import Foundation
import Testing
@testable import OddFrogCore
import BundledFeatures

struct WindowLayoutTests {
    private let visible = CGRect(x: 0, y: 25, width: 1000, height: 600)

    @Test func placementsAnchorToEdges() {
        let twoThirds = WindowFraction(numerator: 2, denominator: 3)
        let threeQuarters = WindowFraction(numerator: 3, denominator: 4)
        #expect(WindowLayout.frame(for: .place(.left, twoThirds), in: visible) == CGRect(x: 0, y: 25, width: 667, height: 600))
        #expect(WindowLayout.frame(for: .place(.right, twoThirds), in: visible) == CGRect(x: 333, y: 25, width: 667, height: 600))
        #expect(WindowLayout.frame(for: .place(.top, threeQuarters), in: visible) == CGRect(x: 0, y: 175, width: 1000, height: 450))
        #expect(WindowLayout.frame(for: .place(.bottom, threeQuarters), in: visible) == CGRect(x: 0, y: 25, width: 1000, height: 450))
        #expect(WindowLayout.frame(for: .maximize, in: visible) == visible)
        #expect(WindowLayout.frame(for: .tidy, in: visible) == nil)
        let secondary = visible.offsetBy(dx: -1500, dy: 900)
        for action in WindowAction.all where action != .tidy {
            #expect(WindowLayout.frame(for: action, in: secondary) == WindowLayout.frame(for: action, in: visible)?.offsetBy(dx: -1500, dy: 900))
        }
        let half = WindowFraction(numerator: 1, denominator: 2)
        #expect(WindowLayout.frame(for: .place(.left, half), in: visible) == CGRect(x: 0, y: 25, width: 500, height: 600))
        #expect(WindowLayout.frame(for: .place(.right, half), in: visible) == CGRect(x: 500, y: 25, width: 500, height: 600))
        #expect(WindowLayout.frame(for: .place(.top, half), in: visible) == CGRect(x: 0, y: 325, width: 1000, height: 300))
        #expect(WindowLayout.frame(for: .place(.bottom, half), in: visible) == CGRect(x: 0, y: 25, width: 1000, height: 300))
    }

    @Test func cascadeKeepsEveryTitleBarVisible() {
        #expect(WindowLayout.cascade(count: 4, in: visible, step: 32) == [
            CGRect(x: 0, y: 121, width: 904, height: 504),
            CGRect(x: 32, y: 89, width: 904, height: 504),
            CGRect(x: 64, y: 57, width: 904, height: 504),
            CGRect(x: 96, y: 25, width: 904, height: 504),
        ])
    }

    @Test func cascadeNeverShrinksBelowHalfScreen() {
        let frames = WindowLayout.cascade(count: 40, in: visible, step: 32)
        #expect(frames.count == 40)
        #expect(frames.allSatisfy { $0.width >= 499 && $0.height >= 299 })
        #expect(frames.allSatisfy { $0.maxX <= 1001 && $0.minY >= 24 })
        #expect(Set(frames.map(\.width)).count == 1)
        #expect(Set(frames.map(\.height)).count == 1)
    }

    @Test func cascadeEdgeCounts() {
        #expect(WindowLayout.cascade(count: 1, in: visible, step: 32) == [visible])
        #expect(WindowLayout.cascade(count: 0, in: visible, step: 32).isEmpty)
        #expect(WindowLayout.cascade(count: -1, in: visible, step: 32).isEmpty)
    }

    @Test func flipRoundTrips() {
        for rect in [visible, CGRect(x: -1400, y: 1000, width: 900, height: 600), CGRect(x: 500, y: -1200, width: 800, height: 700)] {
            #expect(WindowLayout.flipped(WindowLayout.flipped(rect, primaryHeight: 900), primaryHeight: 900) == rect)
        }
        #expect(WindowLayout.flipped(CGRect(x: 10, y: 800, width: 100, height: 50), primaryHeight: 900) == CGRect(x: 10, y: 50, width: 100, height: 50))
    }

    @Test func actionIdsAndTitles() {
        #expect(WindowAction.all.count == 10)
        #expect(Set(WindowAction.all.map(\.id)).count == 10)
        #expect(WindowAction.place(.left, WindowFraction(numerator: 2, denominator: 3)).title == "Left ⅔")
        #expect(WindowAction.tidy.title == "Tidy Windows")
        #expect(WindowAction.all.map(\.id) == [
            "window:place:left:1-2", "window:place:right:1-2",
            "window:place:left:2-3", "window:place:right:2-3",
            "window:place:top:1-2", "window:place:bottom:1-2",
            "window:place:top:3-4", "window:place:bottom:3-4",
            "window:maximize", "window:tidy",
        ])
        let items = WindowAction.all.map { LauncherItem.window(WindowItem(action: $0)) }
        #expect(items.allSatisfy { $0.kindLabel == "Window" && !$0.acceptsArgument })
        var settings = Settings()
        settings.setOverride(ItemOverride(id: "plugin:windows:maximize", enabled: false))
        settings.setOverride(ItemOverride(id: "plugin:windows:tidy", aliases: ["cascade", "cascade"]))
        let applied = settings.apply(to: items)
        #expect(applied.count == 9)
        #expect(!applied.contains { $0.id == "plugin:windows:maximize" })
        #expect(applied.last?.aliases == ["cascade"])
        #expect(SearchEngine.search(query: "cascade", items: applied, weights: [:], maxResults: 8).first?.item.id == "plugin:windows:tidy")
    }
}
