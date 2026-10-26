import AppKit
import BarbarianCore

/// Reads menu bar item windows from the window server.
///
/// Needs no permission. Window titles of other apps come back only with
/// Screen Recording permission.
public enum MenuBarWindowList {
    /// Every status item window in the main display's menu bar, in no
    /// particular order. Includes items that do not fit and are off screen.
    public static func items() -> [MenuBarItem] {
        guard let infos = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap(menuBarItem)
    }

    /// The current frame of one menu bar item, or nil when the item is gone.
    /// Reads the whole list: `.optionIncludingWindow` on its own returns
    /// nothing.
    public static func frame(of windowID: WindowID) -> CGRect? {
        items().first { $0.windowID == windowID }?.frame
    }

    /// Whether the process owns an on-screen menu or popover window.
    public static func hasOpenMenu(ownedBy pid: Int32) -> Bool {
        openMenuOwners().contains(pid)
    }

    /// Processes that own an on-screen menu or popover window.
    public static func openMenuOwners() -> Set<Int32> {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let popUpMenuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return Set(infos.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer >= popUpMenuLevel else { return nil }
            return info[kCGWindowOwnerPID as String] as? Int32
        })
    }

    private static let statusItemLayer = Int(CGWindowLevelForKey(.statusWindow))
    private static let maximumItemHeight: CGFloat = 60

    private static func menuBarItem(from info: [String: Any]) -> MenuBarItem? {
        guard
            info[kCGWindowLayer as String] as? Int == statusItemLayer,
            let windowNumber = info[kCGWindowNumber as String] as? Int,
            let pid = info[kCGWindowOwnerPID as String] as? Int32,
            let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds)
        else {
            return nil
        }
        let isInMainMenuBar = frame.minY == 0 && frame.height <= maximumItemHeight
        guard isInMainMenuBar else { return nil }
        let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return MenuBarItem(
            windowID: WindowID(windowNumber),
            ownerPID: pid,
            ownerName: info[kCGWindowOwnerName as String] as? String ?? "Unknown",
            title: title,
            frame: frame,
            isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false
        )
    }
}
