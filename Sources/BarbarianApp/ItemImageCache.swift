import AppKit
import BarbarianCore
import BarbarianSystem

/// Menu bar items' own images, captured while they are on screen and kept for
/// when they are hidden. Empty while `isOn` is false or without Screen
/// Recording permission.
///
/// Images are seen only in the items menu and the Arrange panel, so items
/// are captured when those open and when a section is revealed.
@Observable
final class ItemImageCache {
    private var images: [WindowID: NSImage] = [:]
    @ObservationIgnored let isOn: () -> Bool

    init(isOn: @escaping () -> Bool) {
        self.isOn = isOn
    }

    func image(of id: WindowID) -> NSImage? {
        isOn() ? images[id] : nil
    }

    /// Captures the on-screen items among `items` and forgets items no longer
    /// among them.
    func capture(_ items: [MenuBarItem]) async {
        guard isOn() else { return }
        let captured = await MenuBarItemImages.capture(items)
        let current = Set(items.map(\.windowID))
        images = images.filter { current.contains($0.key) }
        for (id, image) in captured {
            images[id] = Self.menuBarImage(from: image)
        }
    }

    /// The capture trimmed to its drawn pixels. A one-color image, as most
    /// items are, becomes a template so it follows light and dark mode.
    private static func menuBarImage(from capture: CGImage) -> NSImage? {
        guard let pixels = RGBAPixels(capture), let drawn = pixels.drawnBounds() else { return nil }
        guard let trimmed = capture.cropping(to: drawn) else { return nil }
        let size = NSSize(width: drawn.width / MenuBarItemImages.scale, height: drawn.height / MenuBarItemImages.scale)
        let image = NSImage(cgImage: trimmed, size: size)
        image.isTemplate = pixels.isOneColor(in: drawn)
        return image
    }
}

/// A capture's pixels as 8-bit RGBA, rows top to bottom.
private struct RGBAPixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    private static let visibleAlpha: UInt8 = 40
    private static let maximumGrayChannelSpread: UInt8 = 24

    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drew = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    private func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    /// The smallest rectangle holding every visible pixel.
    func drawnBounds() -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixel(x, y).a >= Self.visibleAlpha {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Whether every visible pixel in `rect` is a shade of gray.
    func isOneColor(in rect: CGRect) -> Bool {
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let p = pixel(x, y)
                guard p.a >= Self.visibleAlpha else { continue }
                let spread = max(p.r, p.g, p.b) - min(p.r, p.g, p.b)
                if spread > Self.maximumGrayChannelSpread { return false }
            }
        }
        return true
    }
}
