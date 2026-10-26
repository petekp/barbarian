import Foundation
import Testing
@testable import BarbarianCore

@Test func eachStateCollapsesTheDividersLeftOfWhatItShows() {
    #expect(HidingState.showingShownOnly.isCollapsed(.hidden))
    #expect(HidingState.showingShownOnly.isCollapsed(.alwaysHidden))
    #expect(!HidingState.showingHidden.isCollapsed(.hidden))
    #expect(HidingState.showingHidden.isCollapsed(.alwaysHidden))
    #expect(!HidingState.showingAll.isCollapsed(.hidden))
    #expect(!HidingState.showingAll.isCollapsed(.alwaysHidden))
}

@Test func onlyAStateShowingAnotherSectionRevealsMore() {
    #expect(HidingState.showingHidden.revealsMore(than: .showingShownOnly))
    #expect(HidingState.showingAll.revealsMore(than: .showingHidden))
    #expect(!HidingState.showingHidden.revealsMore(than: .showingAll))
    #expect(!HidingState.showingHidden.revealsMore(than: .showingHidden))
}

@Test func revealedItemsHideOnceThePointerHasBeenAwayForTheDelay() {
    let policy = AutoRehidePolicy(delay: 4)
    let left = Date(timeIntervalSince1970: 1_000)

    #expect(!policy.shouldRehide(now: left.addingTimeInterval(3), pointerLastInMenuBarAt: left, isMenuOpen: false, isPinnedOpen: false))
    #expect(policy.shouldRehide(now: left.addingTimeInterval(4), pointerLastInMenuBarAt: left, isMenuOpen: false, isPinnedOpen: false))
}

@Test func revealedItemsStayWhileAMenuIsOpenOrTheLayoutWindowPinsThem() {
    let policy = AutoRehidePolicy(delay: 4)
    let left = Date(timeIntervalSince1970: 1_000)
    let later = left.addingTimeInterval(60)

    #expect(!policy.shouldRehide(now: later, pointerLastInMenuBarAt: left, isMenuOpen: true, isPinnedOpen: false))
    #expect(!policy.shouldRehide(now: later, pointerLastInMenuBarAt: left, isMenuOpen: false, isPinnedOpen: true))
}
