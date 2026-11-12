// Draws the app icon and writes Resources/AppIcon.icns. Run with: swift scripts/make-icon.swift
import AppKit

func draw(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let unit = size / 1024
    let plate = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: plate, xRadius: 185 * unit, yRadius: 185 * unit).fill()

    func line(y: CGFloat, width: CGFloat, alpha: CGFloat) {
        NSColor(white: 0.1, alpha: alpha).setFill()
        let rect = NSRect(x: 250 * unit, y: y * unit, width: width * unit, height: 34 * unit)
        NSBezierPath(roundedRect: rect, xRadius: 17 * unit, yRadius: 17 * unit).fill()
    }
    line(y: 730, width: 520, alpha: 0.12)
    line(y: 650, width: 440, alpha: 0.12)
    line(y: 340, width: 500, alpha: 0.12)
    line(y: 260, width: 380, alpha: 0.12)

    let porthole = NSBezierPath(roundedRect: NSRect(x: 190 * unit, y: 430 * unit, width: 644 * unit, height: 164 * unit),
                                xRadius: 44 * unit, yRadius: 44 * unit)
    NSColor.white.setFill()
    porthole.fill()
    NSColor(white: 0.1, alpha: 0.85).setStroke()
    porthole.lineWidth = 14 * unit
    porthole.stroke()
    line(y: 495, width: 420, alpha: 0.9)

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try draw(size: CGFloat(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(size: CGFloat(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
