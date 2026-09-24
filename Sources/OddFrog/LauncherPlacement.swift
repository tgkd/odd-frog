import Foundation

@MainActor
enum LauncherPlacement {
    static var saved: NSPoint? {
        guard let stored = UserDefaults.standard.array(forKey: "LauncherTopCenter") as? [Double], stored.count == 2 else {
            return nil
        }
        return NSPoint(x: stored[0], y: stored[1])
    }

    static func save(_ point: NSPoint) {
        UserDefaults.standard.set([Double(point.x), Double(point.y)], forKey: "LauncherTopCenter")
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: "LauncherTopCenter")
    }
}
