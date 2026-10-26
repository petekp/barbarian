import AppKit

/// `Barbarian --render-app-icon <folder.iconset>` draws the app icon at every
/// size an icon set needs. `scripts/make-app-icon.sh` turns the set into
/// `Resources/AppIcon.icns`.
enum AppIconRenderer {
    /// The macOS icon grid: a 1024-point canvas with an 824-point rounded
    /// tile, leaving room for the tile's shadow.
    private static let canvas: CGFloat = 1024
    private static let tileInset: CGFloat = 100
    private static let tileCornerRadius: CGFloat = 185
    private static let axeSize: CGFloat = 600

    private static let tileColors = [color(0xD2412F), color(0x6A120C)]
    private static let tileEdgeColor = color(0xE0604F)
    private static let axeColors = [color(0xFFFAF0), color(0xE8D9C0)]

    static func run(arguments: [String]) -> Int32 {
        guard let flag = arguments.firstIndex(of: "--render-app-icon"), flag + 1 < arguments.count else {
            FileHandle.standardError.write(Data("usage: Barbarian --render-app-icon <folder.iconset>\n".utf8))
            return 1
        }
        let folder = URL(fileURLWithPath: arguments[flag + 1])
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for points in [16, 32, 128, 256, 512] {
                for scale in [1, 2] {
                    let suffix = scale == 2 ? "@2x" : ""
                    let file = folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
                    try png(pixels: points * scale).write(to: file)
                }
            }
        } catch {
            FileHandle.standardError.write(Data("Could not write the icon set: \(error.localizedDescription)\n".utf8))
            return 1
        }
        return 0
    }

    private static func png(pixels: Int) throws -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        bitmap.size = NSSize(width: canvas, height: canvas)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }

    private static func draw() {
        let tile = NSRect(x: tileInset, y: tileInset, width: canvas - 2 * tileInset, height: canvas - 2 * tileInset)
        let tileShape = NSBezierPath(roundedRect: tile, xRadius: tileCornerRadius, yRadius: tileCornerRadius)
        withShadow(blur: 20, offset: 8, opacity: 0.35) {
            tileColors[1].setFill()
            tileShape.fill()
        }
        NSGradient(colors: tileColors)!.draw(in: tileShape, angle: -90)
        tileEdgeColor.withAlphaComponent(0.6).setStroke()
        tileShape.lineWidth = 3
        tileShape.stroke()

        let axe = BattleAxeIcon.parts(centeredAt: NSPoint(x: tile.midX, y: tile.midY), size: axeSize)
        withShadow(blur: 18, offset: 10, opacity: 0.45) {
            NSColor.black.setFill()
            for part in axe { part.fill() }
        }
        let axeBounds = axe.map(\.bounds).reduce(NSRect.null) { $0.union($1) }
        for part in axe {
            NSGraphicsContext.saveGraphicsState()
            part.addClip()
            NSGradient(colors: axeColors)!.draw(in: axeBounds, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func withShadow(blur: CGFloat, offset: CGFloat, opacity: CGFloat, _ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(opacity)
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: -offset)
        shadow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
