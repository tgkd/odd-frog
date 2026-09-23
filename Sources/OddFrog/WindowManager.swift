import AppKit
@preconcurrency import ApplicationServices
import OddFrogCore

@MainActor
final class WindowManager {
    enum Outcome {
        case done
        case failed(String)
        case needsAccessibility
    }

    private static var promptedForAccess = false

    static var hasAccess: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        guard !promptedForAccess else { return }
        promptedForAccess = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func perform(_ action: WindowAction, cascadeStep: CGFloat) -> Outcome {
        guard Self.hasAccess else {
            Self.requestAccess()
            return .needsAccessibility
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = focusedWindow(of: app.processIdentifier),
              let currentFrame = frame(of: window) else {
            return .failed("No window to move")
        }
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height,
              let screen = screen(for: currentFrame, screens: screens, primaryHeight: primaryHeight) else {
            return .failed("No screen for this window")
        }
        if let target = WindowLayout.frame(for: action, in: screen.visibleFrame) {
            guard setFrame(WindowLayout.flipped(target, primaryHeight: primaryHeight), of: window) else {
                return .failed("The app could not move or resize this window")
            }
            Log.write("window: \(action.id) → \(target.integral)")
            return .done
        }
        let windows = windows(on: screen, screens: screens, primaryHeight: primaryHeight).reversed()
        guard !windows.isEmpty else { return .failed("No windows to tidy") }
        let targets = WindowLayout.cascade(count: windows.count, in: screen.visibleFrame, step: cascadeStep)
        var failures = 0
        for (window, target) in zip(windows, targets) {
            if !setFrame(WindowLayout.flipped(target, primaryHeight: primaryHeight), of: window) {
                failures += 1
            }
        }
        Log.write("window: tidy \(windows.count) windows on \(screen.localizedName), \(failures) failures")
        return failures == 0 ? .done : .failed("Could not move or resize \(failures) of \(windows.count) windows")
    }

    private func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func windows(of pid: pid_t) -> [AXUIElement] {
        attribute(kAXWindowsAttribute, of: AXUIElementCreateApplication(pid)) ?? []
    }

    private func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        if let value: CFTypeRef = attribute(kAXFocusedWindowAttribute, of: app),
           CFGetTypeID(value) == AXUIElementGetTypeID() {
            return (value as! AXUIElement)
        }
        return windows(of: pid).first
    }

    private func subrole(of window: AXUIElement) -> String? {
        attribute(kAXSubroleAttribute, of: window)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position: CFTypeRef = attribute(kAXPositionAttribute, of: window),
              let size: CFTypeRef = attribute(kAXSizeAttribute, of: window),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite,
              dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func set(_ window: AXUIElement, point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private func set(_ window: AXUIElement, size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    private func setFrame(_ frame: CGRect, of window: AXUIElement) -> Bool {
        _ = set(window, size: frame.size)
        let positioned = set(window, point: frame.origin)
        let resized = set(window, size: frame.size)
        return positioned && resized
    }

    private func screen(for frame: CGRect, screens: [NSScreen], primaryHeight: CGFloat) -> NSScreen? {
        let cocoaFrame = WindowLayout.flipped(frame, primaryHeight: primaryHeight)
        var best: NSScreen?
        var largestArea: CGFloat = 0
        for screen in screens {
            let intersection = screen.frame.intersection(cocoaFrame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > largestArea {
                best = screen
                largestArea = area
            }
        }
        return best ?? NSScreen.main
    }

    private func windows(on target: NSScreen, screens: [NSScreen], primaryHeight: CGFloat) -> [AXUIElement] {
        guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var candidates: [pid_t: [(element: AXUIElement, frame: CGRect)]] = [:]
        var result: [AXUIElement] = []
        for entry in entries {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let boundsFrame = CGRect(dictionaryRepresentation: bounds),
                  boundsFrame.width >= 100, boundsFrame.height >= 100,
                  screen(for: boundsFrame, screens: screens, primaryHeight: primaryHeight) == target else { continue }
            if candidates[pid] == nil {
                candidates[pid] = windows(of: pid).compactMap { window in
                    guard subrole(of: window) == kAXStandardWindowSubrole,
                          let frame = frame(of: window) else { return nil }
                    return (window, frame)
                }
            }
            guard let index = candidates[pid]?.firstIndex(where: { candidate in
                abs(candidate.frame.minX - boundsFrame.minX) <= 2 &&
                abs(candidate.frame.minY - boundsFrame.minY) <= 2 &&
                abs(candidate.frame.width - boundsFrame.width) <= 2 &&
                abs(candidate.frame.height - boundsFrame.height) <= 2
            }), let candidate = candidates[pid]?.remove(at: index) else { continue }
            if !result.contains(where: { CFEqual($0, candidate.element) }) {
                result.append(candidate.element)
            }
        }
        return result
    }
}
