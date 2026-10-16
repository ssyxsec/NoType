import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent(".analysis/NoType.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        let bounds = NSRect(x: p * 0.04, y: p * 0.04, width: p * 0.92, height: p * 0.92)
        let background = NSBezierPath(roundedRect: bounds, xRadius: p * 0.22, yRadius: p * 0.22)
        // Match the blue → violet brand mark in the sidebar.
        NSGradient(colors: [NSColor(calibratedRed: 0.035, green: 0.486, blue: 0.835, alpha: 1),
                            NSColor(calibratedRed: 0.537, green: 0.459, blue: 0.788, alpha: 1)])!
            .draw(in: background, angle: -45)
        NSGraphicsContext.saveGraphicsState()
        background.addClip()
        NSGradient(starting: NSColor.white.withAlphaComponent(0.23), ending: NSColor.white.withAlphaComponent(0))!
            .draw(in: bounds, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        background.lineWidth = max(0.5, p * 0.002)
        background.stroke()
        NSColor.white.setFill()
        let heights: [CGFloat] = [0.18, 0.32, 0.48, 0.62, 0.42, 0.26, 0.14]
        for (i, height) in heights.enumerated() {
            let x = p * (0.235 + CGFloat(i) * 0.08)
            NSBezierPath(roundedRect: NSRect(x: x, y: p * (1-height)/2, width: p * 0.045, height: p * height),
                         xRadius: p * 0.022, yRadius: p * 0.022).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
