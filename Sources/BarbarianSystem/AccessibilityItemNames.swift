import ApplicationServices
import BarbarianCore

/// Reads menu bar item names through the Accessibility API, which reports
/// them even when window titles are withheld. Control Center owns many items,
/// and this is how Barbarian tells Wi-Fi from Focus without Screen Recording.
public enum AccessibilityItemNames {
    /// Names keyed by window ID, for items whose window contains the middle of
    /// an Accessibility element. Elements sit a few points inside their
    /// window, so their edges do not line up. An item its app is not drawing
    /// keeps its last frame, which can overlap a drawn item, so on-screen
    /// items win. Empty without Accessibility permission.
    public static func names(for items: [MenuBarItem]) -> [WindowID: String] {
        guard AccessibilityPermission.isGranted else { return [:] }
        var names: [WindowID: String] = [:]
        for (pid, ownedItems) in Dictionary(grouping: items, by: \.ownerPID) {
            for extra in menuBarExtras(of: pid) {
                let containingItems = ownedItems.filter { $0.frame.minX <= extra.midX && extra.midX < $0.frame.maxX }
                guard let item = containingItems.first(where: \.isOnScreen) ?? containingItems.first else { continue }
                names[item.windowID] = extra.name
            }
        }
        return names
    }

    private static let messagingTimeout: Float = 0.25

    private static func menuBarExtras(of pid: Int32) -> [(midX: CGFloat, name: String)] {
        let app = AXUIElement.application(pid, timeout: messagingTimeout)
        guard
            let extrasBar: AXUIElement = app.attribute("AXExtrasMenuBar"),
            let children: [AXUIElement] = extrasBar.attribute(kAXChildrenAttribute)
        else {
            return []
        }
        return children.compactMap { child in
            guard
                let frame = child.frame,
                let name = (child.attribute(kAXDescriptionAttribute) as String?)
                    ?? (child.attribute(kAXTitleAttribute) as String?),
                !name.isEmpty
            else {
                return nil
            }
            return (frame.midX, name)
        }
    }
}
