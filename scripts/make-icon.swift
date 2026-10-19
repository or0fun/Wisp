import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(x: Double(pixels) * 0.07, y: Double(pixels) * 0.07, width: Double(pixels) * 0.86, height: Double(pixels) * 0.86)
        let path = NSBezierPath(roundedRect: rect, xRadius: Double(pixels) * 0.21, yRadius: Double(pixels) * 0.21)
        NSGradient(starting: NSColor(red: 0.63, green: 0.45, blue: 1, alpha: 1), ending: NSColor(red: 0.28, green: 0.28, blue: 0.7, alpha: 1))!.draw(in: path, angle: -65)
        let font = NSFont.systemFont(ofSize: Double(pixels) * 0.52, weight: .medium)
        let symbol = "⌘" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let dimensions = symbol.size(withAttributes: attributes)
        symbol.draw(at: NSPoint(x: (Double(pixels) - dimensions.width) / 2, y: (Double(pixels) - dimensions.height) / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}
