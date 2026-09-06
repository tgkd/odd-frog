import AppKit

// Run from the repository root: swift scripts/generate-icon.swift
// Original vector artwork, rendered at every macOS icon size.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func render(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    color(39, 73, 52).setFill()
    NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                 xRadius: 204, yRadius: 204).fill()

    // A broad head and two raised eyes form the frog silhouette.
    color(185, 222, 130).setFill()
    NSBezierPath(ovalIn: NSRect(x: 208, y: 254, width: 608, height: 438)).fill()
    NSBezierPath(ovalIn: NSRect(x: 254, y: 556, width: 228, height: 228)).fill()
    NSBezierPath(ovalIn: NSRect(x: 542, y: 556, width: 228, height: 228)).fill()

    color(248, 247, 224).setFill()
    NSBezierPath(ovalIn: NSRect(x: 304, y: 606, width: 128, height: 128)).fill()
    NSBezierPath(ovalIn: NSRect(x: 592, y: 606, width: 128, height: 128)).fill()

    color(28, 51, 38).setFill()
    NSBezierPath(ovalIn: NSRect(x: 348, y: 634, width: 54, height: 66)).fill()
    NSBezierPath(ovalIn: NSRect(x: 622, y: 634, width: 54, height: 66)).fill()

    let smile = NSBezierPath()
    smile.move(to: NSPoint(x: 368, y: 452))
    smile.curve(to: NSPoint(x: 656, y: 452),
                controlPoint1: NSPoint(x: 442, y: 378),
                controlPoint2: NSPoint(x: 582, y: 378))
    smile.lineWidth = 28
    smile.lineCapStyle = .round
    color(28, 51, 38).setStroke()
    smile.stroke()

    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
print("Created Resources/AppIcon.icns")
