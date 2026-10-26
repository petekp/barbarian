import AppKit
import BarbarianCore
import BarbarianSystem

/// How Barbarian names and draws other apps' menu bar items.
///
/// An item is drawn with its own image when `ItemImageCache` has one, which
/// needs Screen Recording permission, and with its app's icon otherwise.
struct ItemPresentation {
    private let accessibilityNames: [WindowID: String]
    private let itemCountByOwner: [Int32: Int]

    init(items: [MenuBarItem]) {
        accessibilityNames = AccessibilityItemNames.names(for: items)
        itemCountByOwner = items.reduce(into: [:]) { $0[$1.ownerPID, default: 0] += 1 }
    }

    /// The app's name, unless the app owns several items, as Control Center
    /// does. Then the item's own name, when Barbarian can read it.
    func name(of item: MenuBarItem) -> String {
        let appName = NSRunningApplication(processIdentifier: item.ownerPID)?.localizedName ?? item.ownerName
        guard itemCountByOwner[item.ownerPID, default: 0] > 1 else { return appName }
        if let title = item.title, let systemName = Self.systemItemNames[title] { return systemName }
        if let name = accessibilityNames[item.windowID] { return name }
        if let title = item.title, !title.hasPrefix(Self.untitledWindowPrefix) { return title }
        return appName
    }

    /// AppKit titles a status item's window "Item-0", "Item-1" and so on
    /// when its app gives the item no name.
    private static let untitledWindowPrefix = "Item-"

    /// The item's own image, scaled down to fit `size` points high, or its
    /// app's icon at `size` points square.
    func icon(of item: MenuBarItem, size: CGFloat = 16) -> NSImage? {
        if let captured = ItemImageCache.shared.image(of: item.windowID) {
            let image = captured.copy() as! NSImage
            let scale = min(1, size / captured.size.height)
            image.size = NSSize(width: captured.size.width * scale, height: captured.size.height * scale)
            image.isTemplate = captured.isTemplate
            return image
        }
        guard let icon = NSRunningApplication(processIdentifier: item.ownerPID)?.icon?.copy() as? NSImage else {
            return nil
        }
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    /// Window titles of Control Center's items, which macOS reports only to
    /// processes with Screen Recording permission.
    private static let systemItemNames = [
        "AccessibilityShortcuts": "Accessibility Shortcuts",
        "AudioVideoModule": "Camera and Microphone",
        "BentoBox": "Control Center",
        "FocusModes": "Focus",
        "KeyboardBrightness": "Keyboard Brightness",
        "MusicRecognition": "Music Recognition",
        "NowPlaying": "Now Playing",
        "ScreenMirroring": "Screen Mirroring",
        "StageManager": "Stage Manager",
        "UserSwitcher": "Fast User Switching",
        "WiFi": "Wi-Fi",
    ]
}
