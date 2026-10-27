/// How Barbarian names a menu bar item.
public enum ItemNaming {
    /// A known system item's name. Otherwise the app's name, unless the app
    /// owns several items or is part of macOS with a name nobody knows, such
    /// as SystemUIServer for Siri. Then the item's own name: its
    /// Accessibility name, or its window title unless AppKit made that up.
    /// Window titles need Screen Recording.
    public static func name(
        appName: String,
        isSystemProcess: Bool,
        appItemCount: Int,
        systemItem: SystemItem?,
        title: String?,
        accessibilityName: String?
    ) -> String {
        if let systemItem { return systemItem.name }
        guard appItemCount > 1 || isSystemProcess else { return appName }
        if let accessibilityName { return accessibilityName }
        if let title, !title.hasPrefix(untitledWindowPrefix) { return title }
        return appName
    }

    /// AppKit titles a status item's window "Item-0", "Item-1" and so on
    /// when its app gives the item no name.
    private static let untitledWindowPrefix = "Item-"
}
