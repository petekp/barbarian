import CoreGraphics
import Testing
@testable import BarbarianCore

private let builtInTop: CGFloat = 0
private let externalTop: CGFloat = -1440

private func window(_ id: WindowID, x: CGFloat, y: CGFloat, height: CGFloat, onScreen: Bool = true) -> MenuBarItem {
    MenuBarItem(
        windowID: id, ownerPID: 1, ownerName: "App", title: nil,
        frame: CGRect(x: x, y: y, width: 30, height: height), isOnScreen: onScreen
    )
}

@Test func theActiveMenuBarKeepsItsOwnWindowsAndDropsCopies() {
    let windows = [
        window(1, x: 1800, y: externalTop, height: 24),
        window(2, x: 1100, y: builtInTop, height: 37),
        window(3, x: -8500, y: externalTop, height: 24, onScreen: false),
        window(4, x: -9100, y: builtInTop, height: 37, onScreen: false),
        window(5, x: 0, y: 0, height: 24, onScreen: false),
        window(6, x: 0, y: 0, height: 37, onScreen: false),
        window(7, x: 1730, y: externalTop, height: 37, onScreen: false),
    ]

    let external = MenuBarMembership.items(of: windows, inMenuBarAt: externalTop)
    let builtIn = MenuBarMembership.items(of: windows, inMenuBarAt: builtInTop)

    #expect(Set(external.map(\.windowID)) == [1, 3, 5])
    #expect(Set(builtIn.map(\.windowID)) == [2, 4, 6])
}

@Test func aWindowAtXZeroOnAnotherDisplayIsPlaced() throws {
    let windows = [
        window(1, x: 1800, y: externalTop, height: 24),
        window(2, x: 0, y: externalTop, height: 24, onScreen: false),
    ]

    let layout = try #require(MenuBarLayout(
        items: MenuBarMembership.items(of: windows, inMenuBarAt: externalTop),
        controls: ControlItemIDs(icon: 1, hiddenDivider: 8, alwaysHiddenDivider: 9)
    ))

    #expect(layout.unplacedItems.isEmpty)
    #expect(layout.entries.map(\.id) == [2])
}

@Test func aMenuBarWithNothingOnScreenHasNoItems() {
    let windows = [
        window(1, x: 1800, y: externalTop, height: 24),
        window(2, x: 0, y: 0, height: 37, onScreen: false),
    ]

    #expect(MenuBarMembership.items(of: windows, inMenuBarAt: builtInTop).isEmpty)
}
