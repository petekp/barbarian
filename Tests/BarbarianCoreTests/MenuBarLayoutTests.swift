import CoreGraphics
import Testing
@testable import BarbarianCore

private let controls = ControlItemIDs(icon: 100, hiddenDivider: 101, alwaysHiddenDivider: 102)

private func item(_ id: WindowID, x: CGFloat, width: CGFloat = 30, onScreen: Bool = true, owner: String = "App") -> MenuBarItem {
    MenuBarItem(
        windowID: id, ownerPID: Int32(id), ownerName: owner, title: nil,
        frame: CGRect(x: x, y: 0, width: width, height: 37), isOnScreen: onScreen
    )
}

private func layout(_ items: [MenuBarItem]) throws -> MenuBarLayout {
    try #require(MenuBarLayout(items: items, controls: controls))
}

@Test func itemsFallIntoSectionsByDividerPosition() throws {
    let bar = try layout([
        item(1, x: 900),
        item(102, x: 930, width: 14, owner: "Barbarian"),
        item(2, x: 944),
        item(101, x: 974, width: 14, owner: "Barbarian"),
        item(3, x: 988),
        item(100, x: 1018, owner: "Barbarian"),
        item(4, x: 1048, owner: "Control Center"),
    ])

    #expect(bar.items(in: .alwaysHidden).map(\.windowID) == [1])
    #expect(bar.items(in: .hidden).map(\.windowID) == [2])
    #expect(bar.items(in: .shown).map(\.windowID) == [3])
    #expect(bar.section(of: 4) == nil)
}

@Test func leftDividerSeparatesAlwaysHiddenEvenAfterTheDividersSwap() throws {
    let bar = try layout([
        item(101, x: 900, width: 14),
        item(1, x: 914),
        item(102, x: 944, width: 14),
        item(2, x: 958),
        item(100, x: 988),
    ])

    #expect(bar.role(of: 101) == .alwaysHidden)
    #expect(bar.role(of: 102) == .hidden)
    #expect(bar.items(in: .hidden).map(\.windowID) == [1])
    #expect(bar.items(in: .shown).map(\.windowID) == [2])
}

@Test func itemsThatDoNotFitAreUnplacedAndOffScreen() throws {
    let bar = try layout([
        item(1, x: 0, onScreen: false),
        item(102, x: 900, width: 14),
        item(101, x: 914, width: 14),
        item(2, x: 928),
        item(100, x: 958),
    ])

    #expect(bar.unplacedItems.map(\.windowID) == [1])
    #expect(bar.section(of: 1) == nil)
    #expect(bar.itemsOffScreen.map(\.windowID) == [1])
}

@Test func collapsedSectionItemsKeepTheirSectionWhileOffScreen() throws {
    let bar = try layout([
        item(1, x: -9_100, onScreen: false),
        item(102, x: -9_070, width: 14, onScreen: false),
        item(2, x: -9_056, onScreen: false),
        item(101, x: -9_026, width: 10_000),
        item(3, x: 974),
        item(100, x: 1004),
    ])

    #expect(bar.items(in: .hidden).map(\.windowID) == [2])
    #expect(bar.itemsOffScreen.map(\.windowID) == [1, 2])
}

@Test func layoutNeedsBarbarianIcon() {
    #expect(MenuBarLayout(items: [item(1, x: 900)], controls: controls) == nil)
}

@Test func placingBeforeANeighborDropsLeftOfIt() throws {
    let bar = try layout([item(1, x: 900), item(2, x: 930), item(3, x: 960), item(100, x: 990)])

    #expect(bar.destination(placing: 3, before: 1) == .leftOf(1))
    #expect(bar.destination(placing: 1, before: 2) == nil)
    #expect(bar.destination(placing: 2, before: 2) == nil)
}

@Test func anOffScreenItemRightOfADrawnItemIsHiddenByItsApp() throws {
    let visible: ClosedRange<CGFloat> = 848...1512
    let notDrawn = item(1, x: 1140, onScreen: false)
    let drawn = item(2, x: 1100)
    let doesNotFitAtTheLeftEdge = item(3, x: 862, onScreen: false)
    let doesNotFitPastTheNotch = item(4, x: 830, onScreen: false)
    let collapsed = item(5, x: -4_000, onScreen: false)
    let bar = try layout([collapsed, doesNotFitPastTheNotch, doesNotFitAtTheLeftEdge, drawn, notDrawn, item(100, x: 1200)])

    #expect(bar.isHiddenByItsApp(notDrawn, visibleStatusArea: visible))
    #expect(!bar.isHiddenByItsApp(drawn, visibleStatusArea: visible))
    #expect(!bar.isHiddenByItsApp(doesNotFitAtTheLeftEdge, visibleStatusArea: visible))
    #expect(!bar.isHiddenByItsApp(doesNotFitPastTheNotch, visibleStatusArea: visible))
    #expect(!bar.isHiddenByItsApp(collapsed, visibleStatusArea: visible))
}

@Test func movingToAnIndexAimsAtTheReliableEntryOnItsRight() throws {
    let bar = try layout([
        item(1, x: 900),
        item(102, x: 930, width: 14),
        item(101, x: 944, width: 14),
        item(2, x: 958),
        item(3, x: 988),
        item(4, x: 1018),
        item(100, x: 1048),
    ])

    #expect(bar.destination(moving: 1, to: 2) == .leftOf(2))
    #expect(bar.destination(moving: 1, to: 3, unreliableNeighbors: [3]) == .leftOf(4))
    #expect(bar.destination(moving: 1, to: 5) == .leftOf(100))
    #expect(bar.destination(moving: 4, to: 5) == nil)
    #expect(bar.destination(moving: 2, to: 3) == nil)
    #expect(bar.destination(moving: 2, to: 2) == .leftOf(101))
    #expect(bar.destination(moving: 101, to: 4) == .leftOf(4))
}
