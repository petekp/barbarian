import Foundation

/// Decides when revealed sections hide again.
///
/// Revealed items stay while the pointer is in the menu bar or any menu is
/// open, so a menu opened from a revealed item does not lose its anchor.
/// They hide once the menu bar has been out of use for `delay`: the pointer
/// out of it and no menu open.
public struct AutoRehidePolicy: Sendable, Equatable {
    public var delay: TimeInterval

    public init(delay: TimeInterval = 4) {
        self.delay = delay
    }

    public func shouldRehide(
        now: Date,
        menuBarLastInUseAt: Date,
        isMenuOpen: Bool,
        isPinnedOpen: Bool
    ) -> Bool {
        guard !isPinnedOpen, !isMenuOpen else { return false }
        return now.timeIntervalSince(menuBarLastInUseAt) >= delay
    }
}
