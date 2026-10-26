import AppKit
import BarbarianCore

/// Reads menu bar item windows from the window server.
///
/// Needs no permission. Window titles of other apps come back only with
/// Screen Recording permission.
public enum MenuBarWindowList {
    /// One item's window, wherever it is.
    public static func item(_ windowID: WindowID) -> MenuBarItem? {
        allWindows().first { $0.windowID == windowID }
    }

    /// The current frame of one menu bar item, or nil when the item is gone.
    /// Reads the whole list: `.optionIncludingWindow` on its own returns
    /// nothing.
    public static func frame(of windowID: WindowID) -> CGRect? {
        item(windowID)?.frame
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

    /// Status item windows in every display's menu bar.
    public static func allWindows() -> [MenuBarItem] {
        guard let infos = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap(menuBarItem)
    }

    private static func menuBarItem(from info: [String: Any]) -> MenuBarItem? {
        guard
            info[kCGWindowLayer as String] as? Int == statusItemLayer,
            let windowNumber = info[kCGWindowNumber as String] as? Int,
            let pid = info[kCGWindowOwnerPID as String] as? Int32,
            let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds),
            frame.height <= maximumItemHeight
        else {
            return nil
        }
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
