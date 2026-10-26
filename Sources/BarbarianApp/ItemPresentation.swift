import AppKit
import BarbarianCore
import BarbarianSystem

/// How Barbarian names and draws other apps' menu bar items.
///
/// Without Screen Recording permission Barbarian cannot capture an item's
/// own image, so it shows the owning app's icon.
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
        if let title = item.title { return Self.systemItemNames[title] ?? title }
        return accessibilityNames[item.windowID] ?? appName
    }

    func icon(of item: MenuBarItem, size: CGFloat = 16) -> NSImage? {
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
