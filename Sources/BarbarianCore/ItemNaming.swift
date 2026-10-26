/// How Barbarian names a menu bar item.
public enum ItemNaming {
    /// The app's name, unless the app owns several items, as Control Center
    /// does, or is part of macOS with a name nobody knows, such as
    /// SystemUIServer for Siri. Then the item's own name: a known system
    /// item's window title, its Accessibility name, or its window title
    /// unless AppKit made that up. Window titles need Screen Recording.
    public static func name(
        appName: String,
        isSystemProcess: Bool,
        appItemCount: Int,
        title: String?,
        accessibilityName: String?
    ) -> String {
        guard appItemCount > 1 || isSystemProcess else { return appName }
        if let title, let systemName = systemItemNames[title] { return systemName }
        if let accessibilityName { return accessibilityName }
        if let title, !title.hasPrefix(untitledWindowPrefix) { return title }
        return appName
    }

    /// AppKit titles a status item's window "Item-0", "Item-1" and so on
    /// when its app gives the item no name.
    private static let untitledWindowPrefix = "Item-"

    /// Window titles of Control Center's items.
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
