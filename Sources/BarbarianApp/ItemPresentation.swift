import AppKit
import BarbarianCore
import BarbarianSystem

/// How Barbarian names and draws the items of one menu bar layout.
///
/// Names are worked out once, when the presentation is made. An item is
/// drawn with its own image when `images` has one, which needs Screen
/// Recording permission, and with its app's icon otherwise.
struct ItemPresentation {
    private let names: [WindowID: String]
    private let images: ItemImageCache?

    init(layout: MenuBarLayout?, images: ItemImageCache?) {
        self.init(items: layout.map { $0.entries.compactMap(\.item) + $0.systemItems + $0.unplacedItems } ?? [], images: images)
    }

    init(items: [MenuBarItem], images: ItemImageCache?) {
        self.images = images
        let accessibilityNames = AccessibilityItemNames.names(for: items)
        let itemCountByOwner = items.reduce(into: [Int32: Int]()) { $0[$1.ownerPID, default: 0] += 1 }
        names = Dictionary(items.map { item in
            let app = NSRunningApplication(processIdentifier: item.ownerPID)
            let name = ItemNaming.name(
                appName: app?.localizedName ?? item.ownerName,
                isSystemProcess: app?.bundleURL?.path.hasPrefix("/System/") ?? false,
                appItemCount: itemCountByOwner[item.ownerPID, default: 0],
                title: item.title,
                accessibilityName: accessibilityNames[item.windowID]
            )
            return (item.windowID, name)
        }, uniquingKeysWith: { first, _ in first })
    }

    func name(of item: MenuBarItem) -> String {
        names[item.windowID] ?? item.ownerName
    }

    /// The item's own image, scaled down to fit `size` points high, or its
    /// app's icon at `size` points square.
    func icon(of item: MenuBarItem, size: CGFloat = 16) -> NSImage? {
        if let captured = images?.image(of: item.windowID) {
            let image = captured.copy() as! NSImage
            let scale = min(1, size / captured.size.height)
            image.size = NSSize(width: captured.size.width * scale, height: captured.size.height * scale)
            return image
        }
        guard let icon = NSRunningApplication(processIdentifier: item.ownerPID)?.icon?.copy() as? NSImage else {
            return nil
        }
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}
