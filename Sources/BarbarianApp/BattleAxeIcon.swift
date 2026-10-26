import AppKit

/// Barbarian's menu bar icon: a double-bladed battle axe with a spike on top,
/// tilted to lean right. SF Symbols has no axe, so the icon is drawn here.
enum BattleAxeIcon {
    private static let side: CGFloat = 18
    /// The axe's longest extent. Smaller than the image, because an axe
    /// filling the square looks heavier than the system icons beside it.
    private static let axeSize: CGFloat = 15
    private static let tilt: CGFloat = -40

    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            NSColor.black.setFill()
            for part in parts() { part.fill() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Barbarian"
        return image
    }

    /// The axe's parts, upright in an 18-point square and then tilted.
    private static func parts() -> [NSBezierPath] {
        let centerX = side / 2
        let handleWidth: CGFloat = 1.9
        let handle = NSBezierPath(
            roundedRect: NSRect(x: centerX - handleWidth / 2, y: 0, width: handleWidth, height: side),
            xRadius: handleWidth / 2,
            yRadius: handleWidth / 2
        )

        let spike = NSBezierPath()
        spike.move(to: NSPoint(x: centerX - 1.1, y: 17.4))
        spike.line(to: NSPoint(x: centerX, y: 20.6))
        spike.line(to: NSPoint(x: centerX + 1.1, y: 17.4))
        spike.close()

        var transform = AffineTransform(translationByX: side / 2, byY: side / 2)
        transform.rotate(byDegrees: tilt)
        transform.translate(x: -side / 2, y: -side / 2)

        let parts = [handle, spike, blade(facing: -1), blade(facing: 1)]
        for part in parts { part.transform(using: transform) }
        fitInSquare(parts)
        return parts
    }

    /// Scales and centers `parts` so the tilted axe spans `axeSize`.
    private static func fitInSquare(_ parts: [NSBezierPath]) {
        let bounds = parts.map(\.bounds).reduce(NSRect.null) { $0.union($1) }
        let scale = axeSize / max(bounds.width, bounds.height)
        var transform = AffineTransform(translationByX: side / 2, byY: side / 2)
        transform.scale(scale)
        transform.translate(x: -bounds.midX, y: -bounds.midY)
        for part in parts { part.transform(using: transform) }
    }

    /// A crescent blade on the left (`direction` -1) or right (1) of the handle.
    private static func blade(facing direction: CGFloat) -> NSBezierPath {
        let centerX = side / 2
        let neckBottom: CGFloat = 12.4
        let neckTop: CGFloat = 16.2
        let reach: CGFloat = 6.2
        let edgeBottom = NSPoint(x: centerX + direction * reach, y: 9.8)
        let edgeTop = NSPoint(x: centerX + direction * reach, y: 18.6)
        let edgeMidY = (edgeBottom.y + edgeTop.y) / 2
        let edgeQuarter = (edgeTop.y - edgeBottom.y) / 4
        let bulge = direction * (reach + 1.3)

        let blade = NSBezierPath()
        blade.move(to: NSPoint(x: centerX, y: neckBottom))
        blade.curve(
            to: edgeBottom,
            controlPoint1: NSPoint(x: centerX + direction * reach * 0.45, y: neckBottom),
            controlPoint2: NSPoint(x: centerX + direction * reach * 0.75, y: edgeBottom.y + (neckBottom - edgeBottom.y) * 0.2)
        )
        blade.curve(
            to: edgeTop,
            controlPoint1: NSPoint(x: centerX + bulge, y: edgeMidY - edgeQuarter),
            controlPoint2: NSPoint(x: centerX + bulge, y: edgeMidY + edgeQuarter)
        )
        blade.curve(
            to: NSPoint(x: centerX, y: neckTop),
            controlPoint1: NSPoint(x: centerX + direction * reach * 0.75, y: edgeTop.y - (edgeTop.y - neckTop) * 0.2),
            controlPoint2: NSPoint(x: centerX + direction * reach * 0.45, y: neckTop)
        )
        blade.close()
        return blade
    }
}
