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
            for (item, extra) in matches(of: menuBarExtras(of: pid), in: ownedItems) {
                if let label = extra.label { labels[item.windowID] = label }
            }
        }
        return labels
    }

    /// The items among `candidates` whose app reports no Accessibility
    /// element for them. Control Center reports elements only for the items
    /// it is drawing. An app that reports no menu bar items at all tells
    /// nothing, so its items are not answered. Empty without Accessibility
    /// permission.
    public static func itemsWithoutElement(_ candidates: [MenuBarItem], among items: [MenuBarItem]) -> Set<WindowID> {
        guard AccessibilityPermission.isGranted else { return [] }
        var result: Set<WindowID> = []
        for pid in Set(candidates.map(\.ownerPID)) {
            let extras = menuBarExtras(of: pid)
            guard !extras.isEmpty else { continue }
            let matched = Set(matches(of: extras, in: items.filter { $0.ownerPID == pid }).map(\.item.windowID))
            result.formUnion(candidates.filter { $0.ownerPID == pid && !matched.contains($0.windowID) }.map(\.windowID))
        }
        return result
    }

    private static func matches(of extras: [Extra], in ownedItems: [MenuBarItem]) -> [(item: MenuBarItem, extra: Extra)] {
        extras.compactMap { extra in
            let containingItems = ownedItems.filter { $0.frame.minX <= extra.midX && extra.midX < $0.frame.maxX }
            return (containingItems.first(where: \.isOnScreen) ?? containingItems.first).map { ($0, extra) }
        }
    }

    private struct Extra {
        let midX: CGFloat
        let label: AccessibilityItemLabel?
    }

    private static let messagingTimeout: Float = 0.25

    private static func menuBarExtras(of pid: Int32) -> [Extra] {
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
            let hasLabel = name != nil || identifier != nil
            return Extra(midX: frame.midX, label: hasLabel ? AccessibilityItemLabel(name: name, identifier: identifier) : nil)
        }
    }
}
