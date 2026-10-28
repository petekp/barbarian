import AppKit
import BarbarianCore
import BarbarianSystem

/// How Barbarian names and draws the items of one menu bar layout.
///
/// Names are worked out once, when the presentation is made. An item is
/// drawn with its own image when `images` has one, which needs Screen
/// Recording permission. Otherwise one of macOS's own items is drawn with a
/// symbol that looks like it, and any other item with its app's icon.
struct ItemPresentation {
    private let names: [WindowID: String]
    private let symbolNames: [WindowID: String]
    /// Items whose symbol stands in for their capture.
    private let prefersSymbol: Set<WindowID>
    private let images: ItemImageCache?

    init(layout: MenuBarLayout?, images: ItemImageCache?) {
        self.init(items: layout.map { $0.entries.compactMap(\.item) + $0.systemItems + $0.unplacedItems } ?? [], images: images)
    }

    init(items: [MenuBarItem], images: ItemImageCache?) {
        self.images = images
        let accessibilityLabels = AccessibilityItemLabels.labels(for: items)
        let itemCountByOwner = items.reduce(into: [Int32: Int]()) { $0[$1.ownerPID, default: 0] += 1 }
        var names: [WindowID: String] = [:]
        var symbolNames: [WindowID: String] = [:]
        var prefersSymbol: Set<WindowID> = []
        for item in items {
            let app = NSRunningApplication(processIdentifier: item.ownerPID)
            let label = accessibilityLabels[item.windowID]
            let systemItem = SystemItem(accessibilityIdentifier: label?.identifier, title: item.title, bundleIdentifier: app?.bundleIdentifier)
            names[item.windowID] = ItemNaming.name(
                appName: app?.localizedName ?? item.ownerName,
                isSystemProcess: app?.bundleURL?.path.hasPrefix("/System/") ?? false,
                appItemCount: itemCountByOwner[item.ownerPID, default: 0],
                systemItem: systemItem,
                title: item.title,
                accessibilityName: label?.name
            )
            symbolNames[item.windowID] = systemItem?.symbolName
            if systemItem?.drawsText == true { prefersSymbol.insert(item.windowID) }
        }
        self.names = names
        self.symbolNames = symbolNames
        self.prefersSymbol = prefersSymbol
    }

    func name(of item: MenuBarItem) -> String {
        names[item.windowID] ?? item.ownerName
    }

    /// The item's own image scaled down to fit `size` points high, a symbol
    /// that looks like the item, or its app's icon at `size` points square.
    func icon(of item: MenuBarItem, size: CGFloat = 16) -> NSImage? {
        if !prefersSymbol.contains(item.windowID), let captured = images?.image(of: item.windowID) {
            let image = captured.copy() as! NSImage
            let scale = min(1, size / captured.size.height)
            image.size = NSSize(width: captured.size.width * scale, height: captured.size.height * scale)
            return image
        }
        if let symbolName = symbolNames[item.windowID],
           let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: name(of: item))?
               .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size * 0.8, weight: .regular)) {
            symbol.isTemplate = true
            return symbol
        }
        guard let icon = NSRunningApplication(processIdentifier: item.ownerPID)?.icon?.copy() as? NSImage else {
            return nil
        }
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}
