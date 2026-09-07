import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        let tile = NSBezierPath(roundedRect: NSRect(x: 36, y: 36, width: 440, height: 440), xRadius: 104, yRadius: 104)
        NSGradient(starting: NSColor(calibratedRed: 0.17, green: 0.22, blue: 0.30, alpha: 1), ending: NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.13, alpha: 1))!.draw(in: tile, angle: -90)
        let points = [NSPoint(x: 130, y: 194), NSPoint(x: 253, y: 318), NSPoint(x: 382, y: 245)]
        let link = NSBezierPath()
        link.move(to: points[0]); link.line(to: points[1]); link.line(to: points[2])
        link.lineWidth = 13
        link.lineJoinStyle = .round
        NSColor(calibratedRed: 0.30, green: 0.56, blue: 0.78, alpha: 0.8).setStroke(); link.stroke()
        for (index, point) in points.enumerated() {
            let radius: CGFloat = index == 1 ? 30 : 21
            (index == 1 ? NSColor(calibratedRed: 0.35, green: 0.78, blue: 1, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
