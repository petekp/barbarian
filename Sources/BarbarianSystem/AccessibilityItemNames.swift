import ApplicationServices
import BarbarianCore

/// Reads menu bar item names through the Accessibility API, which reports
/// them even when window titles are withheld. Control Center owns many items,
/// and this is how Barbarian tells Wi-Fi from Focus without Screen Recording.
public enum AccessibilityItemNames {
    /// Names keyed by window ID, for items whose Accessibility element sits
    /// at the same x as the window. Empty without Accessibility permission.
    public static func names(for items: [MenuBarItem]) -> [WindowID: String] {
        guard AccessibilityPermission.isGranted else { return [:] }
        var names: [WindowID: String] = [:]
        for (pid, ownedItems) in Dictionary(grouping: items, by: \.ownerPID) {
            for extra in menuBarExtras(of: pid) {
                guard let item = ownedItems.first(where: { abs($0.frame.minX - extra.x) < 1 }) else { continue }
                names[item.windowID] = extra.name
            }
        }
        return names
    }

    private static let messagingTimeout: Float = 0.25

    private static func menuBarExtras(of pid: Int32) -> [(x: CGFloat, name: String)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard
            let extrasBar: AXUIElement = attribute(app, "AXExtrasMenuBar"),
            let children: [AXUIElement] = attribute(extrasBar, kAXChildrenAttribute)
        else {
            return []
        }
        return children.compactMap { child in
            guard
                let positionValue: AXValue = attribute(child, kAXPositionAttribute),
                let name = (attribute(child, kAXDescriptionAttribute) as String?)
                    ?? (attribute(child, kAXTitleAttribute) as String?),
                !name.isEmpty
            else {
                return nil
            }
            var position = CGPoint.zero
            AXValueGetValue(positionValue, .cgPoint, &position)
            return (position.x, name)
        }
    }

    private static func attribute<Value>(_ element: AXUIElement, _ name: String) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Value
    }
}
