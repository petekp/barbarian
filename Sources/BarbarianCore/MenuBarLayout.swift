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
}

extension MenuBarItem {
    /// macOS reports an item that does not fit at the origin and off screen.
    var hasReportedPosition: Bool {
        isOnScreen || frame.minX != 0
    }
}
