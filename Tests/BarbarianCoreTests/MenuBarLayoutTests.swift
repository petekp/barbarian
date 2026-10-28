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

private let statusArea: ClosedRange<CGFloat> = 848...1512

private func layout(_ items: [MenuBarItem]) throws -> MenuBarLayout {
    try #require(MenuBarLayout(items: items, controls: controls, statusArea: statusArea))
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
}

@Test func layoutNeedsBarbarianIcon() {
    #expect(MenuBarLayout(items: [item(1, x: 900)], controls: controls, statusArea: statusArea) == nil)
}

@Test func placingBeforeANeighborDropsLeftOfIt() throws {
    let bar = try layout([item(1, x: 900), item(2, x: 930), item(3, x: 960), item(100, x: 990)])

    #expect(bar.destination(placing: 3, before: 1) == .leftOf(1))
    #expect(bar.destination(placing: 1, before: 2) == nil)
    #expect(bar.destination(placing: 2, before: 2) == nil)
}

@Test func anOffScreenItemRightOfADrawnItemIsNotDrawn() throws {
    let notDrawn = item(1, x: 1140, onScreen: false)
    let drawn = item(2, x: 1100)
    let doesNotFitAtTheLeftEdge = item(3, x: 862, onScreen: false)
    let doesNotFitPastTheNotch = item(4, x: 830, onScreen: false)
    let collapsed = item(5, x: -4_000, onScreen: false)
    let bar = try layout([collapsed, doesNotFitPastTheNotch, doesNotFitAtTheLeftEdge, drawn, notDrawn, item(100, x: 1200)])

    #expect(bar.notDrawnItems == [notDrawn.windowID])
}

@Test func itemsLeftOfAsManyAsFitCountedFromTheRightDoNotFit() throws {
    let bar = try layout([
        item(1, x: 862, onScreen: false),
        item(2, x: 900),
        item(3, x: 930),
        item(4, x: 1140, onScreen: false),
        item(100, x: 1200),
    ])
    let moved = bar.entries(inOrder: nil, moving: bar.entries[0], to: 2)

    #expect(bar.positionsThatDoNotFitWithEverySectionShown(inOrder: bar.entries) == [0])
    #expect(moved.map(\.id) == [2, 3, 1, 4])
    #expect(bar.positionsThatDoNotFitWithEverySectionShown(inOrder: moved) == [0])
}

@Test func anItemThatHasNotMovedSinceBeforeTheRevealKeepsItsPlace() throws {
    let collapsed = try layout([
        item(102, x: -9_000, width: 14, owner: "Barbarian"),
        item(1, x: -4_100, onScreen: false),
        item(2, x: -4_060, onScreen: false),
        item(101, x: -3_900, width: 14, owner: "Barbarian"),
        item(3, x: 1_016, onScreen: false),
        item(4, x: 1_100),
        item(100, x: 1_200),
    ])
    let revealed = try layout([
        item(1, x: -4_100, onScreen: false),
        item(102, x: 870, width: 14, owner: "Barbarian"),
        item(2, x: 900),
        item(3, x: 1_016, onScreen: false),
        item(101, x: 1_060, width: 14, owner: "Barbarian"),
        item(4, x: 1_100),
        item(100, x: 1_200),
    ])

    let kept = revealed.keepingStaleItems(asIn: collapsed, revealedFrom: .showingShownOnly)

    #expect(kept.entries.map(\.id) == [102, 1, 2, 101, 3, 4])
    #expect(kept.notDrawnItems == [1, 3])
    #expect(kept.section(of: 1) == .hidden)
    #expect(kept.section(of: 3) == .shown)
}

@Test func anItemThatDoesNotFitIsNotStaleWhenNothingWasCollapsed() throws {
    let revealed = try layout([
        item(1, x: 820, onScreen: false),
        item(102, x: 850, width: 14, owner: "Barbarian"),
        item(101, x: 864, width: 14, owner: "Barbarian"),
        item(2, x: 880),
        item(100, x: 1_200),
    ])

    let kept = revealed.keepingStaleItems(asIn: revealed, revealedFrom: .showingAll)

    #expect(kept.notDrawnItems.isEmpty)
    #expect(kept.positionsThatDoNotFitWithEverySectionShown(inOrder: kept.entries) == [0])
}

@Test func movingToAnIndexAimsAtTheReliableEntryOnItsRight() throws {
    let bar = try layout([
        item(1, x: 900),
        item(102, x: 930, width: 14),
        item(101, x: 944, width: 14),
        item(2, x: 958),
        item(3, x: 988, onScreen: false),
        item(4, x: 1018),
        item(100, x: 1048),
    ])

    #expect(bar.destination(moving: 1, to: 2) == .leftOf(2))
    #expect(bar.destination(moving: 1, to: 3) == .leftOf(4))
    #expect(bar.destination(moving: 1, to: 5) == .leftOf(100))
    #expect(bar.destination(moving: 4, to: 5) == nil)
    #expect(bar.destination(moving: 2, to: 2) == .leftOf(101))
    #expect(bar.destination(moving: 101, to: 4) == .leftOf(4))
}

@Test func barbarianWindowsAreFoundByOwnerInLeftToRightOrder() throws {
    let barbarian: Int32 = 42
    func own(_ id: WindowID, x: CGFloat) -> MenuBarItem {
        MenuBarItem(windowID: id, ownerPID: barbarian, ownerName: "Barbarian", title: nil, frame: CGRect(x: x, y: 0, width: 20, height: 37), isOnScreen: true)
    }
    let bar = try #require(MenuBarLayout(
        items: [item(1, x: 900), own(7, x: 930), item(2, x: 950), own(8, x: 980), own(9, x: 1010)],
        barbarianPID: barbarian,
        statusArea: statusArea
    ))

    #expect(bar.controls == ControlItemIDs(icon: 9, hiddenDivider: 8, alwaysHiddenDivider: 7))
}

@Test func aDraggedEntryShowsAtItsTargetAndADropIsReportedOnceTheBarMatches() throws {
    let bar = try layout([item(1, x: 900), item(102, x: 930, width: 14), item(2, x: 944), item(101, x: 974, width: 14), item(100, x: 1018)])

    #expect(bar.entries(inOrder: nil, moving: .item(item(1, x: 900)), to: 2).map(\.id) == [102, 2, 1, 101])
    #expect(bar.hasOrder([1, 102, 2, 101]))
    #expect(!bar.hasOrder([102, 1, 2, 101]))
}
