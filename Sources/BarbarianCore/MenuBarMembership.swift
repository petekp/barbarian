import CoreGraphics

/// Which status item windows belong to one display's menu bar.
///
/// With more than one display, every display has a menu bar and every item
/// has a window in each. The item's own window sits in the active menu bar,
/// the one on the display in use, and the others are copies. When another
/// display becomes active, the item's own window moves there, keeping its
/// window ID, and the copies move out. Barbarian moves and clicks items
/// through their own windows, so it reads the active menu bar.
public enum MenuBarMembership {
    /// The windows in `windows` that belong to the menu bar whose top edge
    /// is at `menuBarTop`.
    ///
    /// A window keeps the height of the menu bar it belongs to, even when
    /// macOS leaves it parked in another one, as it does with copies of items
    /// their app is not drawing. So only windows of this bar's height count.
    /// When two menu bars have the same height, those parked copies cannot be
    /// told apart and are included.
    public static func items(of windows: [MenuBarItem], inMenuBarAt menuBarTop: CGFloat) -> [MenuBarItem] {
        let onThisBar = windows.filter { $0.frame.minY == menuBarTop }
        guard let height = mostCommonHeight(of: onThisBar.filter(\.isOnScreen)) else { return [] }
        return onThisBar.filter { $0.frame.height == height }
    }

    private static func mostCommonHeight(of windows: [MenuBarItem]) -> CGFloat? {
        let counts = windows.reduce(into: [CGFloat: Int]()) { $0[$1.frame.height, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }
}
