import CoreGraphics

/// The window IDs of Barbarian's own status items.
public struct ControlItemIDs: Sendable, Equatable {
    public let icon: WindowID
    public let hiddenDivider: WindowID
    public let alwaysHiddenDivider: WindowID

    public init(icon: WindowID, hiddenDivider: WindowID, alwaysHiddenDivider: WindowID) {
        self.icon = icon
        self.hiddenDivider = hiddenDivider
        self.alwaysHiddenDivider = alwaysHiddenDivider
    }

    var dividers: Set<WindowID> { [hiddenDivider, alwaysHiddenDivider] }
}

/// Barbarian's reading of the menu bar at one moment: which managed item
/// sits where, and in which section.
public struct MenuBarLayout: Sendable, Equatable {
    public enum Entry: Hashable, Sendable, Identifiable {
        case item(MenuBarItem)
        case divider(Divider, WindowID)

        public var item: MenuBarItem? {
            if case .item(let item) = self { item } else { nil }
        }

        public var id: WindowID {
            switch self {
            case .item(let item): item.windowID
            case .divider(_, let id): id
            }
        }
    }

    /// Managed items and both dividers, left to right. Everything here sits
    /// left of Barbarian's icon.
    public let entries: [Entry]

    /// Managed items macOS gives no position, because they do not fit in
    /// the menu bar.
    public let unplacedItems: [MenuBarItem]

    public let controls: ControlItemIDs

    /// The left edge of the leftmost drawn item up to Barbarian's icon,
    /// dividers included.
    private let leftmostOnScreenX: CGFloat

    /// Reads a layout from the window list.
    ///
    /// Divider roles follow position, not identity: the left divider always
    /// separates Always Hidden from Hidden. That keeps the sections in order
    /// when someone drags one divider past the other.
    public init?(items: [MenuBarItem], controls: ControlItemIDs) {
        guard let icon = items.first(where: { $0.windowID == controls.icon }) else { return nil }
        self.controls = controls

        let placed = items.filter { $0.hasReportedPosition && $0.windowID != controls.icon }
        let managed = placed
            .filter { $0.frame.minX < icon.frame.minX }
            .sorted { $0.frame.minX < $1.frame.minX }

        var dividersSeen = 0
        entries = managed.map { item in
            guard controls.dividers.contains(item.windowID) else { return .item(item) }
            defer { dividersSeen += 1 }
            return .divider(dividersSeen == 0 ? .alwaysHidden : .hidden, item.windowID)
        }
        unplacedItems = items.filter { !$0.hasReportedPosition && !controls.dividers.contains($0.windowID) }
        leftmostOnScreenX = (managed + [icon]).filter(\.isOnScreen).map(\.frame.minX).min() ?? icon.frame.minX
    }

    /// The divider that currently plays each role.
    public func windowID(of divider: Divider) -> WindowID? {
        for case .divider(let role, let id) in entries where role == divider { return id }
        return nil
    }

    public func role(of dividerID: WindowID?) -> Divider? {
        for case .divider(let role, let id) in entries where id == dividerID { return role }
        return nil
    }

    public func section(of id: WindowID) -> MenuBarSection? {
        var section = MenuBarSection.alwaysHidden
        for entry in entries {
            switch entry {
            case .divider(.alwaysHidden, _): section = .hidden
            case .divider(.hidden, _): section = .shown
            case .item(let item) where item.windowID == id: return section
            case .item: continue
            }
        }
        return nil
    }

    public func items(in section: MenuBarSection) -> [MenuBarItem] {
        entries.compactMap { entry in
            guard case .item(let item) = entry, self.section(of: item.windowID) == section else { return nil }
            return item
        }
    }

    /// Managed items that are not on screen right now, for any reason:
    /// their section is collapsed, or they do not fit.
    public var itemsOffScreen: [MenuBarItem] {
        entries.compactMap { entry in
            guard case .item(let item) = entry, !item.isOnScreen else { return nil }
            return item
        } + unplacedItems
    }

    /// Whether `item` is off screen because its app is not drawing it, as Now
    /// Playing is when nothing plays, rather than because it does not fit.
    ///
    /// macOS drops items that do not fit from the left end of the bar, so
    /// they sit left of every drawn item. An item its app is not drawing keeps
    /// its last frame, inside the visible bar and right of a drawn item.
    public func isHiddenByItsApp(_ item: MenuBarItem, visibleStatusArea: ClosedRange<CGFloat>) -> Bool {
        !item.isOnScreen
            && visibleStatusArea.contains(item.frame.minX)
            && visibleStatusArea.contains(item.frame.maxX)
            && item.frame.minX > leftmostOnScreenX
    }

    /// Where to drop `item` so it lands immediately left of `neighbor`.
    /// Nil when it is already there or the drop names the item itself.
    public func destination(placing item: WindowID, before neighbor: WindowID) -> MoveDestination? {
        guard item != neighbor else { return nil }
        let ids = entries.map(\.id)
        if let index = ids.firstIndex(of: item), index + 1 < ids.count, ids[index + 1] == neighbor {
            return nil
        }
        return .leftOf(neighbor)
    }

    /// Where to drop `item` so it becomes the rightmost item of `section`.
    public func destination(appending item: WindowID, to section: MenuBarSection) -> MoveDestination? {
        let rightBoundary: WindowID? = switch section {
        case .alwaysHidden: windowID(of: .alwaysHidden)
        case .hidden: windowID(of: .hidden)
        case .shown: controls.icon
        }
        guard let rightBoundary else { return nil }
        if rightBoundary == controls.icon {
            return entries.last?.id == item ? nil : .leftOf(rightBoundary)
        }
        return destination(placing: item, before: rightBoundary)
    }

    /// Where to drop `item` so it lands at `index` among the other items of
    /// `section`, counting from the left.
    ///
    /// The move aims at the item that will sit on its right. Items in
    /// `unreliableNeighbors`, such as ones their app is not drawing, report
    /// stale frames, so the move aims past them at the next item instead.
    public func destination(
        inserting item: WindowID,
        into section: MenuBarSection,
        at index: Int,
        unreliableNeighbors: Set<WindowID> = []
    ) -> MoveDestination? {
        let others = items(in: section).map(\.windowID).filter { $0 != item }
        let rightNeighbor = others.dropFirst(min(index, others.count)).first { !unreliableNeighbors.contains($0) }
        if let rightNeighbor {
            return destination(placing: item, before: rightNeighbor)
        }
        return destination(appending: item, to: section)
    }
}

extension MenuBarItem {
    /// macOS reports an item that does not fit at the origin and off screen.
    /// The origin is the top left of the main display, so on a display above
    /// or left of it an item can sit at x = 0 with another y.
    var hasReportedPosition: Bool {
        isOnScreen || frame.origin != .zero
    }
}
