import Foundation

/// Decides when revealed sections hide again.
///
/// Revealed items stay while the pointer is in the menu bar or any menu is
/// open, so a menu opened from a revealed item does not lose its anchor.
/// They hide once the pointer has been out of the menu bar for `delay`.
public struct AutoRehidePolicy: Sendable, Equatable {
    public var delay: TimeInterval

    public init(delay: TimeInterval = 4) {
        self.delay = delay
    }

    public func shouldRehide(
        now: Date,
        pointerLastInMenuBarAt: Date,
        isMenuOpen: Bool,
        isPinnedOpen: Bool
    ) -> Bool {
        guard !isPinnedOpen, !isMenuOpen else { return false }
        return now.timeIntervalSince(pointerLastInMenuBarAt) >= delay
    }
}
