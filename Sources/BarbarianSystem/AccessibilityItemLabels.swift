import ApplicationServices
import BarbarianCore

/// An item's name and identifier as the Accessibility API reports them.
public struct AccessibilityItemLabel: Sendable {
    public let name: String?
    /// Such as `com.apple.menuextra.wifi`. Only some apps set one.
    public let identifier: String?
}

/// Reads menu bar item labels through the Accessibility API, which reports
/// them even when window titles are withheld. Control Center owns many items,
/// and this is how Barbarian tells Wi-Fi from Focus without Screen Recording.
public enum AccessibilityItemLabels {
    /// Labels keyed by window ID, for items whose window contains the middle of
    /// an Accessibility element. Elements sit a few points inside their
    /// window, so their edges do not line up. An item its app is not drawing
    /// keeps its last frame, which can overlap a drawn item, so on-screen
    /// items win. Empty without Accessibility permission.
    public static func labels(for items: [MenuBarItem]) -> [WindowID: AccessibilityItemLabel] {
        guard AccessibilityPermission.isGranted else { return [:] }
        var labels: [WindowID: AccessibilityItemLabel] = [:]
        for (pid, ownedItems) in Dictionary(grouping: items, by: \.ownerPID) {
            for extra in menuBarExtras(of: pid) {
                let containingItems = ownedItems.filter { $0.frame.minX <= extra.midX && extra.midX < $0.frame.maxX }
                guard let item = containingItems.first(where: \.isOnScreen) ?? containingItems.first else { continue }
                labels[item.windowID] = extra.label
            }
        }
        return labels
    }

    private static let messagingTimeout: Float = 0.25

    private static func menuBarExtras(of pid: Int32) -> [(midX: CGFloat, label: AccessibilityItemLabel)] {
        let app = AXUIElement.application(pid, timeout: messagingTimeout)
        guard
            let extrasBar: AXUIElement = app.attribute("AXExtrasMenuBar"),
            let children: [AXUIElement] = extrasBar.attribute(kAXChildrenAttribute)
        else {
            return []
        }
        return children.compactMap { child in
            guard let frame = child.frame else { return nil }
            let name = [kAXDescriptionAttribute, kAXTitleAttribute]
                .lazy.compactMap { child.attribute($0) as String? }
                .first { !$0.isEmpty }
            let identifier: String? = child.attribute(kAXIdentifierAttribute)
            guard name != nil || identifier != nil else { return nil }
            return (frame.midX, AccessibilityItemLabel(name: name, identifier: identifier))
        }
    }
}
