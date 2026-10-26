/// The parts of the menu bar Barbarian manages, left to right:
/// Always Hidden, then Hidden, then Shown.
///
/// Two of Barbarian's own status items, the dividers, mark the boundaries.
/// The Always Hidden divider sits left of the Hidden divider. Items right of
/// Barbarian's icon, such as the clock and Control Center, belong to macOS
/// and are not managed.
public enum MenuBarSection: String, CaseIterable, Sendable {
    case alwaysHidden
    case hidden
    case shown

    public var title: String {
        switch self {
        case .alwaysHidden: "Always Hidden"
        case .hidden: "Hidden"
        case .shown: "Shown"
        }
    }
}

public enum Divider: String, CaseIterable, Sendable {
    /// Separates Always Hidden from Hidden.
    case alwaysHidden
    /// Separates Hidden from Shown.
    case hidden
}

/// Which sections are on screen.
public enum HidingState: Sendable, Equatable {
    case showingShownOnly
    case showingHidden
    case showingAll

    /// Whether a divider is stretched to push the items on its left off screen.
    public func isCollapsed(_ divider: Divider) -> Bool {
        switch (self, divider) {
        case (.showingShownOnly, _): true
        case (.showingHidden, .alwaysHidden): true
        case (.showingHidden, .hidden): false
        case (.showingAll, _): false
        }
    }
}
