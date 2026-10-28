import BarbarianCore

/// One display's menu bar and the items in it, read from one window list.
public struct MenuBar: Sendable {
    public let display: MenuBarDisplay
    /// The items in this menu bar, in no particular order, on screen or not.
    /// See `MenuBarMembership`.
    public let items: [MenuBarItem]

    public init(display: MenuBarDisplay, windows: [MenuBarItem]) {
        self.display = display
        items = MenuBarMembership.items(of: windows, inMenuBarAt: display.bounds.minY)
    }

    /// The menu bar holding the window `isAnchor` picks. Anchored on
    /// Barbarian's icon window, this is the active menu bar.
    public init?(holding isAnchor: (MenuBarItem) -> Bool, in windows: [MenuBarItem]) {
        guard
            let anchor = windows.first(where: isAnchor),
            let display = MenuBarDisplay.holding(anchor.frame)
        else {
            return nil
        }
        self.init(display: display, windows: windows)
    }
}
